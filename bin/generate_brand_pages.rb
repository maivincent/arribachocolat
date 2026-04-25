#!/usr/bin/env ruby
# Generate one stub .md file per brand under brands/.
# Run this whenever a new brand is added (called automatically by publish.sh).

require 'yaml'
require 'fileutils'

def slugify(name)
  name
    .unicode_normalize(:nfd).gsub(/\p{Mn}/, '')  # strip combining diacritics
    .downcase
    .gsub(/[''']/, '')                             # strip apostrophes
    .gsub(/[^a-z0-9]+/, '-')
    .gsub(/^-|-$/, '')
end

brands = {}

Dir.glob('_i18n/fr/_posts/*.md').each do |file|
  fm = File.read(file).match(/\A---\n(.*?)\n---\n/m)
  next unless fm

  data = YAML.safe_load(fm[1])
  cats = data&.[]('categories') || []
  cats.each do |brand|
    slug = slugify(brand)
    brands[slug] = brand
  end
end

FileUtils.mkdir_p('brands')

# Remove stubs for brands that no longer exist
Dir.glob('brands/*.md').each do |f|
  slug = File.basename(f, '.md')
  File.delete(f) unless brands.key?(slug)
end

brands.each do |slug, brand_name|
  path = "brands/#{slug}.md"
  content = <<~MD
    ---
    layout: brand
    title: "#{brand_name.gsub('"', '\\"')}"
    brand_name: "#{brand_name.gsub('"', '\\"')}"
    permalink: /brands/#{slug}/
    ---
  MD
  File.write(path, content)
end

puts "Generated #{brands.size} brand pages in brands/"
