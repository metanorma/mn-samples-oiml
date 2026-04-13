#!/usr/bin/env ruby
# Generates the fl-build matrix entries from metanorma.yml
# Output: JSON array of matrix include entries

require 'yaml'
require 'json'

MANIFEST = ARGV[0] || 'metanorma.yml'
SOURCES_DIR = 'sources'

config = YAML.load_file(MANIFEST)
files = config.dig('metanorma', 'source', 'files') || []

prefix = '/mn-samples-oiml/'

entries = files.map do |entry|
  src = entry.is_a?(Hash) ? entry['files'] : entry
  parent_dir = File.dirname(src)          # e.g. "sources/r144/1" or "sources/b022-e23"
  grandchild_dir = File.basename(parent_dir)  # e.g. "1" or "b022-e23"
  grandparent_dir = File.basename(File.dirname(parent_dir))  # e.g. "r144" or "sources"
  name = File.basename(parent_dir)
  is_collection = src =~ /collection\.yml\z/

  # Handle subdocuments: sources/r144/1/document.adoc -> name "r144-1"
  if grandparent_dir == 'r144' && name =~ /\A\d+\z/
    name = "r144-#{name}"
  end

  if is_collection
    {
      'name' => name,
      'artifact' => "mn-#{name}",
      'dir' => '',
      'xml' => 'collection.presentation.xml',
      'url' => name,
      'prefix' => prefix
    }
  else
    {
      'name' => name,
      'artifact' => 'mn',
      'dir' => "documents/#{parent_dir.sub('sources/', '')}",
      'xml' => 'document.presentation.xml',
      'url' => name,
      'prefix' => prefix
    }
  end
end

puts entries.to_json