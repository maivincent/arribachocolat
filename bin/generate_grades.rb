#!/usr/bin/env ruby
# Parse all .md posts and generate grades.yml data file

require 'yaml'
require 'fileutils'
require 'set'

score_re = /(?:final evaluation|evaluaci[oó]n final|evaluaci[oó]n|evaluación final|note finale|évaluation finale|evaluation finale)\s*[:\s]*\s*([0-9]+(?:\.[0-9]+)?)\s*\/\s*25/i

grades = {}
grades['<=20'] = []
(20..24).each do |i|
  grades[i.to_s] = []
  grades["#{i}.5"] = []
end
grades['25'] = []

# Track seen URLs to avoid duplicates from different language versions
seen_urls = Set.new

# Find all markdown post files
post_dirs = [
  '_i18n/fr/_posts',
  '_i18n/en/_posts',
  '_i18n/es/_posts'
]

post_dirs.each do |dir|
  next unless Dir.exist?(dir)
  Dir.glob("#{dir}/*.md").each do |file|
    content = File.read(file)
    # Remove front matter
    content.gsub!(/\A---\n.*?\n---\n/m, '')
    # Remove emphasis
    content.gsub!(/\*\*|__|\*|_|<strong>|<\/strong>|<em>|<\/em>/i, '')
    
    m = content.match(score_re)
    next unless m
    
    score = m[1].to_f
    # Bucket scores: <=20 stays <=20, 20+ gets rounded to nearest 0.5
    if score <= 20
      label = '<=20'
    else
      bucket_value = (score * 2).round / 2.0
      bucket_value = 25 if bucket_value > 25
      label = bucket_value == bucket_value.to_i ? bucket_value.to_i.to_s : bucket_value.to_s
    end
    
    # Extract post metadata from frontmatter for display
    fm = File.read(file).match(/\A---\n(.*?)\n---\n/m)
    data = YAML.safe_load(fm[1]) if fm
    
    title = data&.[]('title') || File.basename(file)
    date = data&.[]('date') || ''
    
    # Generate URL from filename
    # Format: YYYY-MM-DD-slug.md => /category/YYYY/MM/DD/slug.html
    basename = File.basename(file, '.md')
    category = (data&.[]('categories')&.first || 'post').downcase
    
    if basename =~ /^(\d{4})-(\d{2})-(\d{2})-(.+)$/
      year, month, day, slug = $1, $2, $3, $4
      url = "/#{category}/#{year}/#{month}/#{day}/#{slug}.html"
    else
      url = "/#{basename}/"
    end
    
    # Skip if we've already seen this URL (from another language version)
    next if seen_urls.include?(url)
    seen_urls.add(url)
    
    grades[label] << { 'title' => title, 'date' => date, 'url' => url }
  end
end

# Create _data directory if it doesn't exist
FileUtils.mkdir_p('_data')

# Write grades.yml
File.open('_data/grades.yml', 'w') do |f|
  f.write(grades.to_yaml)
end

total = grades.values.map(&:size).reduce(0, :+)
puts "Generated grades.yml with #{total} posts across #{grades.keys.size} buckets"
