#!/usr/bin/env ruby

# Translate French posts to other languages using DeepL.
#
# Usage:
#   DEEPL_AUTH_KEY=<key> ruby bin/translate_posts.rb
#   ruby bin/translate_posts.rb               # reads key from .deepl_key if present
#   ruby bin/translate_posts.rb --dry-run     # list files that would be translated
#   ruby bin/translate_posts.rb               # read key from .deepl_key if present
#
# The script translates only the markdown body (everything after the front matter)
# and leaves the YAML front matter keys intact (except it updates the `title`).

require 'yaml'
require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'time'
require 'fileutils'

options = {
  dry_run: false,
  langs: %w[en es],
  source_lang: 'FR',
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-n', '--dry-run', 'Show which files would be translated without calling DeepL or writing output') do
    options[:dry_run] = true
  end

  opts.on('-l', '--langs LANGS', 'Comma-separated list of target languages (default: en,es)') do |v|
    options[:langs] = v.split(',').map(&:strip).reject(&:empty?)
  end

  opts.on('-h', '--help', 'Show help') do
    puts opts
    exit 0
  end
end.parse!

root = File.expand_path('..', __dir__)

# Prefer environment variable, but allow a local key file for safety (not checked in).
api_key = ENV['DEEPL_AUTH_KEY'] || ENV['DEEPL_API_KEY']
key_path = File.join(root, '.deepl_key')
if api_key.to_s.strip.empty? && File.exist?(key_path)
  api_key = File.read(key_path).strip
end

if api_key.to_s.strip.empty? && !options[:dry_run]
  warn "ERROR: Set DEEPL_AUTH_KEY (or DEEPL_API_KEY) in the environment, or create #{key_path} with your key."
  exit 1
end

api_url = ENV['DEEPL_API_URL'] || 'https://api-free.deepl.com/v2/translate'

# Helper: split YAML front matter + body
def split_front_matter(content)
  return [nil, content] unless content.start_with?("---\n")

  parts = content.split(/^---\s*\n/, 3)
  # parts: ["", "...yaml...", "body..."]
  if parts.size == 3
    [parts[1], parts[2]]
  else
    [nil, content]
  end
end

## Extract a contiguous grades block (lines with labels and numeric values) and return [before, grades_lines_array, after]
def extract_grades_block(text)
  lines = text.lines
  n = lines.length
  start_idx = nil
  end_idx = nil

  # be permissive: treat lines containing ": <number>" as grade lines
  grade_line_re = /:\s*[0-9]+(?:\.[0-9]+)?/

  (0...n).each do |i|
    if lines[i] =~ grade_line_re
      start_idx ||= i
      end_idx = i
    elsif start_idx && end_idx && i == end_idx + 1
      break
    end
  end

  return [text, [], ""] unless start_idx

  heading_idx = start_idx - 1
  if heading_idx >= 0 && lines[heading_idx] =~ /^\s*#+\s+/ && (start_idx - heading_idx) <= 2
    start_idx = heading_idx
  end

  before = lines[0...start_idx].join
  grades = lines[start_idx..end_idx].map(&:chomp)
  after = lines[(end_idx+1)..-1]&.join || ""
  [before, grades, after]
end

## Try to find a template labels list in existing translations for `lang`.
## Returns array of label strings (including formatting like underscores) or nil.
def find_template_labels(root, lang)
  dest_dir = File.join(root, '_i18n', lang, '_posts')
  return nil unless Dir.exist?(dest_dir)

  Dir.glob(File.join(dest_dir, '*.md')).each do |p|
    content = File.read(p)
    _fm, body = split_front_matter(content)
    before, grades, after = extract_grades_block(body)
    next if grades.empty?
    labels = grades.map do |line|
      parts = line.split(':', 2)
      parts[0].strip
    end
    return labels unless labels.empty?
  end
  nil
end

# DeepL translate helper
def deepl_translate(text, target_lang, source_lang, api_key, api_url, options)
  puts "Translating to #{target_lang} (#{text.length} chars)..." if options[:dry_run] == false
  uri = URI(api_url)
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "DeepL-Auth-Key #{api_key}"
  req.set_form_data(
    'text' => text,
    'source_lang' => source_lang,
    'target_lang' => target_lang.upcase,
    'preserve_formatting' => '1',
    'split_sentences' => 'nonewlines'
  )

  res = Net::HTTP.start(
    uri.hostname,
    uri.port,
    use_ssl: uri.scheme == 'https',
    open_timeout: 10,
    read_timeout: 30
  ) do |http|
    http.request(req)
  end

  unless res.is_a?(Net::HTTPSuccess)
    raise "DeepL API error #{res.code}: #{res.body}"
  end

  body = JSON.parse(res.body)
  (body['translations'] || []).map { |t| t['text'] }.join("\n\n")
end

source_dir = File.join(root, '_i18n', 'fr', '_posts')

# Try to find a template labels list in existing translations for `lang`.
# Returns array of label strings (including formatting like underscores) or nil.

unless Dir.exist?(source_dir)
  warn "ERROR: source directory not found: #{source_dir}"
  exit 1
end

translated = []
skipped = []

Dir.glob(File.join(source_dir, '*.md')).sort.each do |src_path|
  filename = File.basename(src_path)
  content = File.read(src_path)

  front_matter_text, body = split_front_matter(content)
  front_matter = front_matter_text ? YAML.safe_load(front_matter_text) : {}

  options[:langs].each do |lang|

# Build a grades block using template labels (if provided) and the numeric values from source_grades_lines
def build_grades_block(template_labels, source_grades_lines)
  # If no template labels provided, we'll fall back to language defaults elsewhere.
  return source_grades_lines.join("\n") if source_grades_lines.empty?

  # Determine heading, labels and final label based on template_labels or language hints.
  # If template_labels is a Hash mapping (lang => labels), handle accordingly; otherwise
  # assume it's an Array of five labels.

  # Normalize input: if first line is a heading like '###', drop it but remember to emit localized heading.
  heading = nil
  lines = source_grades_lines.dup
  if lines[0] =~ /^\s*#+\s*/
    heading = lines.shift.strip
  end

  # Extract numeric values (in order) and final score/fraction
  numbers = []
  final_fraction = nil
  lines.each do |ln|
    # final line often contains bold markers and a fraction like 23/25
    if ln =~ /\*\*/
      m = ln.match(/([0-9]+(?:\.[0-9]+)?\s*\/\s*25)/)
      final_fraction = m ? m[1].gsub('\s','') : nil
      next
    end
    m = ln.match(/([0-9]+(?:\.[0-9]+)?)/)
    numbers << (m ? m[1] : '')
  end

  # If template_labels is an Array, use as-is; otherwise caller may supply nil.
  labels = template_labels.is_a?(Array) ? template_labels : nil

  # Attempt to infer language from labels if possible (look for obvious words)
  lang = nil
  if labels
    # quick heuristic
    first = labels[0].to_s.downcase
    lang = 'es' if first.include?('original') || first.include?('originalidad')
    lang = 'en' if first.include?('uniqu') || first.include?('uniqueness')
  end

  # Fallback label sets per language
  fallbacks = {
    'en' => ['Uniqueness', 'Finesse', 'Comfort', 'Intensity', 'Overall impression'],
    'es' => ['Originalidad', 'Fineza', 'Reconfortante', 'Intensidad', 'Impresión general']
  }

  # Choose labels: prefer provided template_labels, else fallbacks based on lang, else English.
  chosen = labels || (lang && fallbacks[lang]) || fallbacks['en']

  # Choose heading and final label by lang
  heading_map = { 'en' => '### Evaluation', 'es' => '### Evaluación' }
  final_map = { 'en' => '**Final evaluation**', 'es' => '**Nota final**' }
  heading_emit = heading_map[lang] || heading_map['en']
  final_label_emit = final_map[lang] || final_map['en']

  out = []
  out << heading_emit
  # Emit five labeled lines with single underscores and two trailing spaces to preserve linebreaks
  chosen.each_with_index do |lbl, idx|
    # sanitize label: remove surrounding underscores/asterisks and trailing colons
    clean = lbl.to_s.gsub(/^\s+|\s+$/, '').gsub(/^_+|_+$|^\*+|\*+$/, '').sub(/:$/, '')
    val = numbers[idx] || ''
    out << "_#{clean}_: #{val}  "
  end
  # Emit final fraction if found, else attempt to sum numbers
  if final_fraction
    out << "\n#{final_label_emit}: #{final_fraction}"
  else
    # compute a total if numbers look numeric
    if numbers.all? { |n| n.to_s =~ /^\d+(?:\.\d+)?$/ }
      total = numbers.map(&:to_f).sum
      total_s = (total % 1.0 == 0) ? total.to_i.to_s : total.to_s
      out << "\n#{final_label_emit}: #{total_s}/25"
    else
      out << "\n#{final_label_emit}:"
    end
  end

  out.join("\n")
end
    dest_dir = File.join(root, '_i18n', lang, '_posts')
    FileUtils.mkdir_p(dest_dir)
    dest_path = File.join(dest_dir, filename)

    if File.exist?(dest_path)
      skipped << dest_path
      next
    end

    if options[:dry_run]
      translated << dest_path
      next
    end

    # Extract grades block from source and avoid translating it
    before_text, source_grades_lines, after_text = extract_grades_block(body)

    # Translate body parts separately so we can reinsert a controlled grades block
    translated_before = before_text.strip.empty? ? "" : deepl_translate(before_text, lang, options[:source_lang], api_key, api_url, options)
    translated_after  = after_text.strip.empty?  ? "" : deepl_translate(after_text,  lang, options[:source_lang], api_key, api_url, options)

    # Build grades block from template labels if available (keeps numbers from source)
    template_labels = find_template_labels(root, lang)
    if source_grades_lines.empty?
      grades_block = ""
    else
      # build_grades_block defined below
      grades_block = build_grades_block(template_labels, source_grades_lines)
    end

    translated_body = [translated_before.to_s.strip, grades_block.to_s.strip, translated_after.to_s.strip].reject(&:empty?).join("\n\n")

    # Translate title if present
    translated_title = nil
    if front_matter.is_a?(Hash) && front_matter['title'].is_a?(String)
      translated_title = deepl_translate(front_matter['title'], lang, options[:source_lang], api_key, api_url, options).strip
      front_matter['title'] = translated_title
    end

    # Translate tags if present and ensure tags are an array
    if front_matter.is_a?(Hash) && front_matter['tags']
      tags = front_matter['tags'].is_a?(Array) ? front_matter['tags'] : [front_matter['tags'].to_s]
      translated_tags = tags.map do |t|
        t = t.to_s.strip
        next t if t.empty?

        # Hard-coded overrides for specific tags (avoid calling DeepL for these)
        lc = t.downcase
        if lc == 'noir'
          case lang
          when 'es'
            'Oscuro'
          when 'en'
            'Dark'
          else
            t
          end
        else
          deepl_translate(t, lang, options[:source_lang], api_key, api_url, options).strip
        end
      end
      front_matter['tags'] = translated_tags
      translated_tags_var = translated_tags
    end

    # Do not add translation metadata fields (translated_from/translated_at/translated_to)
    # — these were removed to keep generated front matter minimal.

    output = "---\n"
    # Always write the title as a quoted YAML scalar to match site conventions.
    # Use the translated_title (if set) as a reliable source; fall back to front_matter['title'].
    title_to_emit = translated_title || (front_matter.is_a?(Hash) && front_matter['title'])
    if title_to_emit
      title_val = title_to_emit.to_s
      escaped = title_val.gsub('"', '\\"')
      output += "title: \"#{escaped}\"\n"
      front_matter.delete('title') if front_matter.is_a?(Hash)
    end

    # Emit tags and categories as inline bracket lists to match site conventions,
    # then dump any remaining front_matter. We remove emitted keys to avoid duplication.
    if front_matter.is_a?(Hash)
      # Emit tags: handle both String and Array (use translated_tags_var if present)
      tags_val = defined?(translated_tags_var) ? translated_tags_var : front_matter['tags']
      if tags_val
        tags_arr = tags_val.is_a?(Array) ? tags_val : [tags_val.to_s]
        tags_arr = tags_arr.map(&:to_s).reject(&:empty?)
        unless tags_arr.empty?
          formatted = tags_arr.map { |t| "\"#{t.gsub('"', '\\\"')}\"" }.join(', ')
          output += "tags: [#{formatted}]\n"
        end
        front_matter.delete('tags')
      end

      # Emit categories: handle both String and Array
      cats_val = front_matter['categories']
      if cats_val
        cats_arr = cats_val.is_a?(Array) ? cats_val : [cats_val.to_s]
        cats_arr = cats_arr.map(&:to_s).reject(&:empty?)
        unless cats_arr.empty?
          formatted = cats_arr.map { |c| "\"#{c.gsub('"', '\\\"')}\"" }.join(', ')
          output += "categories: [#{formatted}]\n"
        end
        front_matter.delete('categories')
      end

      unless front_matter.empty?
        output += YAML.dump(front_matter).sub(/^---\n/, '')
      end
    end

    output += "---\n\n"
    output += translated_body.strip + "\n"

    File.write(dest_path, output)
    translated << dest_path
  end
end

puts "Translated #{translated.size} files (#{options[:langs].join(', ')})"
translated.each do |path|
  puts "  - #{path}"
end
puts "Skipped #{skipped.size} existing files" if skipped.any?
