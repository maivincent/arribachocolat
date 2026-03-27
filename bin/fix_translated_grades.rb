#!/usr/bin/env ruby
# Fix grades block in translated posts by reading numbers from French source posts
# and emitting standardized labels per language.

require 'yaml'
require 'fileutils'
require 'optparse'

root = File.expand_path('..', __dir__)
source_dir = File.join(root, '_i18n', 'fr', '_posts')
langs = %w[en es]

def split_front_matter(content)
  return [nil, content] unless content.start_with?("---\n")
  parts = content.split(/^---\s*\n/, 3)
  parts.size == 3 ? [parts[1], parts[2]] : [nil, content]
end

def extract_grades_block(text)
  lines = text.lines
  n = lines.length
  start_idx = nil
  end_idx = nil
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

LABELS = {
  'en' => ['Uniqueness', 'Finesse', 'Comfort', 'Intensity', 'Overall impression'],
  'es' => ['Originalidad', 'Fineza', 'Reconfortante', 'Intensidad', 'Impresión general']
}

HEADING = { 'en' => '### Evaluation', 'es' => '### Evaluación' }
FINAL_LABEL = { 'en' => '**Final evaluation**', 'es' => '**Nota final**' }

Dir.glob(File.join(source_dir, '*.md')).sort.each do |src_path|
  filename = File.basename(src_path)
  src_content = File.read(src_path)
  src_fm_text, src_body = split_front_matter(src_content)
  before, src_grades, after = extract_grades_block(src_body)
  next if src_grades.empty?

  # extract numbers and final fraction
  numbers = []
  final_fraction = nil
  src_grades.each do |ln|
    if ln =~ /\*\*/
      m = ln.match(/([0-9]+(?:\.[0-9]+)?\s*\/\s*25)/)
      final_fraction = m ? m[1].gsub('\s','') : nil
      next
    end
    m = ln.match(/([0-9]+(?:\.[0-9]+)?)/)
    numbers << (m ? m[1] : '')
  end

  langs.each do |lang|
    dest = File.join(root, '_i18n', lang, '_posts', filename)
    next unless File.exist?(dest)
    content = File.read(dest)
    fm_text, body = split_front_matter(content)
    fm = fm_text ? YAML.safe_load(fm_text) : {}

    # build grades block
    labels = LABELS[lang]
    heading = HEADING[lang]
    final_label = FINAL_LABEL[lang]
    out = []
    out << heading
    labels.each_with_index do |lbl, idx|
      val = numbers[idx] || ''
      out << "_#{lbl}_: #{val}  "
    end
    if final_fraction
      out << "\n#{final_label}: #{final_fraction}"
    else
      if numbers.all? { |n| n.to_s =~ /^\d+(?:\.\d+)?$/ }
        total = numbers.map(&:to_f).sum
        total_s = (total % 1.0 == 0) ? total.to_i.to_s : total.to_s
        out << "\n#{final_label}: #{total_s}/25"
      else
        out << "\n#{final_label}:"
      end
    end
    grades_block = out.join("\n")

    # replace old grades block in body
    b_before, b_grades, b_after = extract_grades_block(body)
    new_body = b_before + grades_block + "\n\n" + b_after

    # write file back preserving front matter and fm keys
    output = "---\n"
    if fm.is_a?(Hash)
      title_val = fm.delete('title')
      if title_val
        escaped = title_val.to_s.gsub('"', '\\\"')
        output += "title: \"#{escaped}\"\n"
      end

      tags_val = fm.delete('tags')
      if tags_val
        tags_arr = tags_val.is_a?(Array) ? tags_val : [tags_val.to_s]
        formatted = tags_arr.map { |t| "\"#{t.to_s.gsub('"', '\\\"')}\"" }.join(', ')
        output += "tags: [#{formatted}]\n"
      end

      cats_val = fm.delete('categories')
      if cats_val
        cats_arr = cats_val.is_a?(Array) ? cats_val : [cats_val.to_s]
        formatted = cats_arr.map { |c| "\"#{c.to_s.gsub('"', '\\\"')}\"" }.join(', ')
        output += "categories: [#{formatted}]\n"
      end

      unless fm.empty?
        output += YAML.dump(fm).sub(/^---\n/, '')
      end
    end
    output += "---\n\n"
    output += new_body

    File.write(dest, output)
    puts "Updated grades in #{dest}"
  end
end
