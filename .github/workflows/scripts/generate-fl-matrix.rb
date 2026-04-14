#!/usr/bin/env ruby
# Generates the fl-build matrix entries from metanorma.yml
# Output: JSON array of matrix include entries

require 'yaml'
require 'json'

MANIFEST = ARGV[0] || 'metanorma.yml'
SOURCES_DIR = 'sources'

config = YAML.load_file(MANIFEST)
files = config.dig('metanorma', 'source', 'files') || []

# Determine collection names from metanorma.yml to exclude sub-documents
collection_names = files
  .map { |entry| entry.is_a?(Hash) ? entry['files'] : entry }
  .select { |src| src =~ /collection\.yml\z/ }
  .map { |src| File.basename(File.dirname(src)) }

prefix = '/mn-samples-oiml/'

entries = files.map do |entry|
  src = entry.is_a?(Hash) ? entry['files'] : entry
  parent_dir = File.dirname(src)          # e.g. "sources/r144/1" or "sources/b022-e23"
  name = File.basename(parent_dir)       # e.g. "1", "b022-e23", "main"
  grandparent_dir = File.basename(File.dirname(parent_dir))  # e.g. "r144", "sources"
  is_collection = src =~ /collection\.yml\z/

  if is_collection
    {
      'name' => name,
      'artifact' => 'mn',
      'dir' => 'documents/collection-output',
      'xml' => 'collection.presentation.xml',
      'url' => name,
      'prefix' => prefix
    }
  elsif collection_names.include?(grandparent_dir)
    # Subdocument within a collection
    collection_name = grandparent_dir
    url = "#{collection_name}/#{name}"
    {
      'name' => url.gsub('/', '-'),
      'artifact' => 'mn',
      'dir' => "documents/#{collection_name}",
      'xml' => "#{name}/document.presentation.xml",
      'url' => url,
      'prefix' => prefix
    }
  else
    url = parent_dir.sub('sources/', '')
    {
      'name' => url.gsub('/', '-'),
      'artifact' => 'mn',
      'dir' => "documents/#{url}",
      'xml' => 'document.presentation.xml',
      'url' => url,
      'prefix' => prefix
    }
  end
end.compact

puts entries.to_json
