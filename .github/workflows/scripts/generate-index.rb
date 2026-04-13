#!/usr/bin/env ruby
# Generates an index.html for the OIML Firelight site.
# Reads metanorma.yml to discover documents and collections,
# extracts titles from source files, and outputs index.html.

require 'yaml'
require 'erb'
require 'pathname'

MANIFEST = Pathname.new(ARGV[0] || 'metanorma.yml')
OUTPUT = Pathname.new(ARGV[1] || 'dist/index.html')
SOURCES_DIR = Pathname.new('sources')
PREFIX = '/mn-samples-oiml/'

# Map of source file to URL slug and description
def process_manifest(manifest_path)
  config = YAML.load_file(manifest_path)
  files = config.dig('metanorma', 'source', 'files') || []

  files.map do |entry|
    src = entry.is_a?(Hash) ? entry['files'] : entry
    src_path = SOURCES_DIR.join(src)

    if src =~ /collection\.yml\z/
      collection_name = File.basename(File.dirname(src))
      title = collection_title(src_path) || collection_name
      {
        name: collection_name,
        url: "#{PREFIX}#{collection_name}/",
        title: title,
        is_collection: true,
      }
    else
      doc_name = File.basename(File.dirname(src))
      title = document_title(src_path) || doc_name
      {
        name: doc_name,
        url: "#{PREFIX}#{doc_name}/",
        title: title,
        is_collection: false,
      }
    end
  end
end

def collection_title(collection_yml_path)
  # Try to get title from the collection manifest
  config = YAML.load_file(collection_yml_path)
  title = config.dig('bibdata', 'title', 0, 'content') ||
          config.dig('bibdata', 'title', 'content')
  return title if title

  # Fall back: look at the first document in the collection
  docref = config.dig('manifest', 'docref', 0)
  return nil unless docref

  first_doc = docref['fileref'] || docref['file']
  return nil unless first_doc

  first_doc_path = SOURCES_DIR.join(File.dirname(collection_yml_path), first_doc)
  document_title(first_doc_path)
end

DOC_TITLE_REGEX = /^= (.+)$/
TITLE_ATTR_REGEX = /^:title-main-en: (.+)$/

def document_title(document_adoc_path)
  return nil unless File.exist?(document_adoc_path)

  # First line is the title (e.g. "= Metrological regulation for load cells")
  first_line = File.readlines(document_adoc_path, chomp: true).first
  if first_line && first_line =~ DOC_TITLE_REGEX
    return $1
  end

  # Fall back to :title-main-en: attribute
  File.foreach(document_adoc_path) do |line|
    if line =~ TITLE_ATTR_REGEX
      return $1
    end
  end
  nil
end

INDEX_TEMPLATE = ERB.new <<~HTML, trim_mode: '-'
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>OIML Documents</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 0 20px; }
      h1 { margin-bottom: 30px; }
      .doc { border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
      .doc h2 { margin: 0 0 10px 0; font-size: 18px; }
      .doc p { margin: 0 0 10px 0; color: #555; }
      .doc a { font-size: 16px; }
      .doc ul { margin: 0; padding-left: 20px; }
    </style>
  </head>
  <body>
    <h1>OIML Documents</h1>
    <% docs.each do |doc| %>
    <div class="doc">
      <h2><%= doc[:title] %></h2>
      <p><%= doc[:is_collection] ? 'Collection' : 'Document' %>: <code><%= doc[:name] %></code></p>
      <a href="<%= doc[:url] %>">Open</a>
    </div>
    <% end %>
  </body>
  </html>
HTML

docs = process_manifest(MANIFEST)

# Sort: collections first, then individual documents, both alphabetically
docs.sort_by! { |d| [d[:is_collection] ? 0 : 1, d[:name]] }

OUTPUT.parent.mkpath
OUTPUT.write(INDEX_TEMPLATE.result(binding))

puts "Generated #{OUTPUT}"
