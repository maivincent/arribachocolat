#!/usr/bin/env ruby
# Generate one stub .md file per tag under tags/.
# Run this whenever a new tag is added (called automatically by publish.sh).

require 'yaml'
require 'fileutils'

def slugify(name)
  name
    .unicode_normalize(:nfd).gsub(/\p{Mn}/, '')  # strip combining diacritics
    .downcase
    .gsub(/[^a-z0-9]+/, '-')                      # non-alphanumeric → hyphen (matches Jekyll/Liquid slugify)
    .gsub(/^-|-$/, '')
end

tags = {}

Dir.glob('_i18n/fr/_posts/*.md').each do |file|
  fm = File.read(file).match(/\A---\n(.*?)\n---\n/m)
  next unless fm

  data = YAML.safe_load(fm[1])
  (data&.[]('tags') || []).each do |tag|
    slug = slugify(tag)
    tags[slug] = tag
  end
end

FileUtils.mkdir_p('tags')

# Remove stubs for tags that no longer exist
Dir.glob('tags/*.md').each do |f|
  slug = File.basename(f, '.md')
  File.delete(f) unless tags.key?(slug)
end

tags.each do |slug, tag_name|
  path = "tags/#{slug}.md"
  content = <<~MD
    ---
    layout: tag
    title: "#{tag_name.gsub('"', '\\"')}"
    tag_name: "#{tag_name.gsub('"', '\\"')}"
    permalink: /tags/#{slug}/
    ---
  MD
  File.write(path, content)
end

puts "Generated #{tags.size} tag pages in tags/"
