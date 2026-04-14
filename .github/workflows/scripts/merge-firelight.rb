#!/usr/bin/env ruby
# Merges Firelight HTML artifacts into the built site and injects Firelight links.
# Usage: ruby merge-firelight.rb <site-artifact-dir> <fl-artifact-dir> <output-dir>

require 'fileutils'
require 'pathname'
require 'find'
require 'nokogiri'
require 'set'

SITE_DIR = Pathname.new(ARGV[0] || 'site')
FL_DIR = Pathname.new(ARGV[1] || 'fl')
OUTPUT_DIR = Pathname.new(ARGV[2] || 'dist')

OUTPUT_DIR.mkpath

# Copy entire site to output (copy contents, not the dir itself)
if SITE_DIR.exist?
  FileUtils.cp_r(Dir.glob("#{SITE_DIR}/*"), OUTPUT_DIR)
else
  puts "WARNING: Site directory #{SITE_DIR} does not exist"
  exit 1
end

# Discover Firelight entries from separate artifact directories (fl/fl-<name>/<url>/index.html)
firelight_entries = [] # [name, src_path]
if FL_DIR.exist?
  Dir.glob("#{FL_DIR}/fl-*").each do |artifact_dir|
    next unless File.directory?(artifact_dir)
    Find.find(artifact_dir) do |path|
      next unless File.directory?(path)
      if File.exist?(File.join(path, 'index.html'))
        rel = Pathname.new(path).relative_path_from(Pathname.new(artifact_dir)).to_s
        firelight_entries << [rel, path]
        Find.prune
      end
    end
  end
end

firelight_names = firelight_entries.map(&:first)
puts "Discovered Firelight entries: #{firelight_names.join(', ')}"

# Merge Firelight HTML into site
firelight_entries.each do |name, src_path|
  site_dest = OUTPUT_DIR.join('documents', name, 'firelight')

  site_dest.parent.mkpath
  FileUtils.cp_r(src_path, site_dest)
  puts "Merged Firelight HTML: #{site_dest}"
end

# Inject Firelight links into index.html using Nokogiri
index_html = OUTPUT_DIR.join('index.html')
if index_html.exist?
  doc = Nokogiri::HTML(index_html.read)
  injected = []
  used_sections = Set.new

  firelight_names.each do |name|
    firelight_path = "documents/#{name}/firelight/index.html"
    doc_path = "documents/#{name}/document.html"

    target_section = nil

    # Strategy 1: Find section containing a link to documents/<name>/document.html
    doc.css('.document').each do |section|
      next if used_sections.include?(section)
      has_link = section.css('a').any? { |a| a['href']&.include?(doc_path) }
      if has_link
        target_section = section
        break
      end
    end

    # Strategy 2: For collections, find section linking to collection-output/
    unless target_section
      doc.css('.document').each do |section|
        next if used_sections.include?(section)
        has_collection = section.css('a').any? { |a| a['href']&.include?('collection-output/') }
        if has_collection
          target_section = section
          break
        end
      end
    end

    if target_section
      access_div = target_section.at_css('.doc-access')
      if access_div
        # Skip if Firelight link already exists
        existing = access_div.css('a').any? { |a| a['href']&.include?(firelight_path) }
        unless existing
          firelight_div = Nokogiri::HTML::DocumentFragment.parse(
            %Q{<div class="doc-access-button-firelight"><a href="./#{firelight_path}">Firelight</a></div>}
          )
          pdf_button = access_div.at_css('.doc-access-button-pdf')
          if pdf_button
            pdf_button.add_previous_sibling(firelight_div)
          else
            access_div.add_child(firelight_div)
          end
          used_sections << target_section
          injected << name
          puts "Injected Firelight link for: #{name}"
        end
      end
    else
      puts "WARNING: Could not find index section for: #{name}"
    end
  end

  if injected.any?
    index_html.write(doc.to_html)
    puts "Updated index.html with Firelight links for: #{injected.join(', ')}"
  end
else
  puts "WARNING: index.html not found at #{index_html}"
end

puts "Merged site at: #{OUTPUT_DIR}"