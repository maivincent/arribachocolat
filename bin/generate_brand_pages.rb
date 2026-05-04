#!/usr/bin/env ruby
# Generate one stub .md file per brand under brands/.
# Run this whenever a new brand is added (called automatically by publish.sh).

require 'yaml'
require 'fileutils'

def slugify(name)
  name
    .unicode_normalize(:nfd).gsub(/\p{Mn}/, '')  # strip combining diacritics
    .downcase
    .gsub(/[^a-z0-9]+/, '-')                      # non-alphanumeric → hyphen (matches Jekyll/Liquid slugify)
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

# Build _data/brand_descriptions.yml from info_marques/{lang}/{slug}.md
descriptions = {}
%w[fr en es].each do |lang|
  descriptions[lang] = {}
  brands.each_key do |slug|
    info_path = "info_marques/#{lang}/#{slug}.md"
    next unless File.exist?(info_path)
    descriptions[lang][slug] = File.read(info_path).strip
  end
end

FileUtils.mkdir_p('_data')
File.write('_data/brand_descriptions.yml', descriptions.to_yaml)
puts "Generated _data/brand_descriptions.yml (#{descriptions.values.sum(&:size)} entries)"

# Build _data/brand_intro.yml from info_marques/{lang}/introduction.md
intro = {}
%w[fr en es].each do |lang|
  path = "info_marques/#{lang}/introduction.md"
  intro[lang] = File.exist?(path) ? File.read(path).strip : ''
end
File.write('_data/brand_intro.yml', intro.to_yaml)
puts "Generated _data/brand_intro.yml"
