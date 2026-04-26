#!/usr/bin/env ruby
# Generate one stub .md file per tag under tags/, and _data/tag_fr_slugs.yml
# mapping every tag name (any language) to its French slug.
# Run whenever a new tag is added (called automatically by publish.sh).

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

# Build cross-language mappings by pairing tags by position across same-filename posts
tag_fr_slugs = {}       # any-language tag name → French slug
tag_translations = {}   # French slug → { 'fr' => name, 'en' => name, 'es' => name }

Dir.glob('_i18n/fr/_posts/*.md').each do |fr_file|
  fr_fm = File.read(fr_file).match(/\A---\n(.*?)\n---\n/m)
  next unless fr_fm

  fr_data = YAML.safe_load(fr_fm[1])
  fr_tags = fr_data&.[]('tags') || []
  next if fr_tags.empty?

  basename = File.basename(fr_file)

  fr_tags.each do |t|
    slug = slugify(t)
    tag_fr_slugs[t] = slug
    tag_translations[slug] ||= {}
    tag_translations[slug]['fr'] = t
  end

  %w[en es].each do |lang|
    lang_file = "_i18n/#{lang}/_posts/#{basename}"
    next unless File.exist?(lang_file)

    lang_fm = File.read(lang_file).match(/\A---\n(.*?)\n---\n/m)
    next unless lang_fm

    lang_data = YAML.safe_load(lang_fm[1])
    lang_tags = lang_data&.[]('tags') || []

    lang_tags.each_with_index do |lang_tag, i|
      next unless fr_tags[i]
      fr_slug = slugify(fr_tags[i])
      tag_fr_slugs[lang_tag] = fr_slug
      tag_translations[fr_slug] ||= {}
      tag_translations[fr_slug][lang] ||= lang_tag
    end
  end
end

FileUtils.mkdir_p('_data')
File.write('_data/tag_fr_slugs.yml', tag_fr_slugs.sort.to_h.to_yaml)
puts "Generated _data/tag_fr_slugs.yml with #{tag_fr_slugs.size} entries"
File.write('_data/tag_translations.yml', tag_translations.sort.to_h.to_yaml)
puts "Generated _data/tag_translations.yml with #{tag_translations.size} entries"
