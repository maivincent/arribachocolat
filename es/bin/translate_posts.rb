#!/usr/bin/env ruby

# Translate French posts to other languages using DeepL.
#
# Usage:
#   DEEPL_AUTH_KEY=<key> ruby bin/translate_posts.rb
#   ruby bin/translate_posts.rb               # reads key from .deepl_key if present
#   ruby bin/translate_posts.rb --dry-run     # list files that would be translated
#   ruby bin/translate_posts.rb --force       # overwrite existing translations
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
  force: false,
  dry_run: false,
  langs: %w[en es],
  source_lang: 'FR',
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-f', '--force', 'Overwrite existing translations') do
    options[:force] = true
  end

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
  return source_grades_lines.join("\n") if template_labels.nil? || source_grades_lines.empty?

  # extract numbers from source lines in order
  numbers = source_grades_lines.map do |line|
    m = line.match(/([0-9]+(?:\.[0-9]+)?)(?:\s*\/\s*25)?/)
    m ? m[1] : ''
  end

  out_lines = []
  template_labels.each_with_index do |label, idx|
    num = numbers[idx] || ''
    out_lines << "#{label}: #{num}".rstrip
  end
  out_lines.join("\n")
end
    dest_dir = File.join(root, '_i18n', lang, '_posts')
    FileUtils.mkdir_p(dest_dir)
    dest_path = File.join(dest_dir, filename)

    if File.exist?(dest_path) && !options[:force]
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
    if front_matter.is_a?(Hash) && front_matter['title'].is_a?(String)
      translated_title = deepl_translate(front_matter['title'], lang, options[:source_lang], api_key, api_url, options)
      front_matter['title'] = translated_title.strip
    end

    # Translate tags if present and ensure tags are an array
    if front_matter.is_a?(Hash) && front_matter['tags']
      tags = front_matter['tags'].is_a?(Array) ? front_matter['tags'] : [front_matter['tags'].to_s]
      translated_tags = tags.map do |t|
        t = t.to_s.strip
        next t if t.empty?
        # keep short tags untranslated? here we translate all tags
        deepl_translate(t, lang, options[:source_lang], api_key, api_url, options).strip
      end
      front_matter['tags'] = translated_tags
    end

    # Add metadata about translation
    if front_matter.is_a?(Hash)
      front_matter['translated_from'] = 'fr'
      front_matter['translated_at'] = Time.now.utc.iso8601
      front_matter['translated_to'] = lang
    end

    output = "---\n"
    output += YAML.dump(front_matter).sub(/^---\n/, '')
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
puts "Skipped #{skipped.size} existing files (use --force to overwrite)" if skipped.any?
