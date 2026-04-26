#!/usr/bin/env ruby
# Check tag consistency across all three language versions of each post.
# Reports:
#   1. Per-post issues: missing files, tag count mismatches, wrong translations
#   2. Cross-post issues: same French tag translated multiple ways in a language

require 'yaml'

def slugify(name)
  name
    .unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
    .downcase
    .gsub(/[^a-z0-9]+/, '-')
    .gsub(/^-|-$/, '')
end

def tags_for(file)
  fm = File.read(file).match(/\A---\n(.*?)\n---\n/m)
  return [] unless fm
  data = YAML.safe_load(fm[1])
  data&.[]('tags') || []
end

tag_fr_slugs = YAML.safe_load(File.read('_data/tag_fr_slugs.yml')) || {}

def fr_slug_for(tag, mapping)
  mapping[tag] || slugify(tag)
end

per_post_errors = []

# fr_slug → lang → { translation → [files using it] }
translation_variants = Hash.new { |h, k| h[k] = { 'fr' => {}, 'en' => {}, 'es' => {} } }

Dir.glob('_i18n/fr/_posts/*.md').sort.each do |fr_file|
  basename = File.basename(fr_file)
  fr_tags  = tags_for(fr_file)
  next if fr_tags.empty?

  fr_slugs = fr_tags.map { |t| slugify(t) }

  # Record French tags under their own slug
  fr_tags.each do |t|
    slug = slugify(t)
    translation_variants[slug]['fr'][t] ||= []
    translation_variants[slug]['fr'][t] << basename
  end

  %w[en es].each do |lang|
    lang_file = "_i18n/#{lang}/_posts/#{basename}"

    unless File.exist?(lang_file)
      per_post_errors << { file: basename, lang: lang, issue: "file missing" }
      next
    end

    lang_tags = tags_for(lang_file)

    if lang_tags.size != fr_tags.size
      per_post_errors << {
        file: basename, lang: lang,
        issue: "tag count: #{lang_tags.size} vs fr #{fr_tags.size}",
        fr: fr_tags, lang_tags: lang_tags
      }
      next
    end

    lang_tags.each_with_index do |lang_tag, i|
      resolved = fr_slug_for(lang_tag, tag_fr_slugs)

      # Record translation variant: fr_slug → lang → translation → files
      fr_slug = fr_slugs[i]
      translation_variants[fr_slug][lang][lang_tag] ||= []
      translation_variants[fr_slug][lang][lang_tag] << basename

      unless resolved == fr_slug
        per_post_errors << {
          file: basename, lang: lang,
          issue: "position #{i}: '#{lang_tag}' → #{resolved} ≠ fr '#{fr_tags[i]}' (#{fr_slug})",
          fr: fr_tags, lang_tags: lang_tags
        }
      end
    end
  end
end

# Find French tags that have more than one distinct translation in a language
variant_errors = []
translation_variants.sort.each do |fr_slug, langs|
  %w[en es].each do |lang|
    variants = langs[lang]
    next if variants.size <= 1
    variant_errors << { fr_slug: fr_slug, lang: lang, variants: variants }
  end
end

# --- Report ---

separator = '-' * 60

if per_post_errors.empty?
  puts "Per-post checks: no issues found."
else
  puts "Per-post issues (#{per_post_errors.size}):\n\n"
  per_post_errors.each do |e|
    puts "#{e[:file]}  [#{e[:lang]}]"
    puts "  #{e[:issue]}"
    if e[:fr]
      puts "  fr:  #{e[:fr].join(', ')}"
      puts "  #{e[:lang]}:  #{e[:lang_tags].join(', ')}" if e[:lang_tags]
    end
    puts
  end
end

puts separator

if variant_errors.empty?
  puts "Translation variants: no issues found."
else
  puts "Inconsistent translations (#{variant_errors.size}):\n\n"
  variant_errors.each do |e|
    puts "fr '#{e[:fr_slug]}'  [#{e[:lang]}]:"
    e[:variants].each do |name, files|
      puts "  '#{name}'  (#{files.size}x) — #{files.first(3).join(', ')}#{files.size > 3 ? ', ...' : ''}"
    end
    puts
  end
end
