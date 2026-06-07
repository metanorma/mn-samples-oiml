#!/usr/bin/env ruby
# frozen_string_literal: true

# Transcribe PDFs using GLM-OCR (Z.AI layout parsing API).
# Saves full JSON response + extracted markdown to .glm-ocr-cache/.
#
# Usage:
#   bundle exec ruby scripts/ocr_transcribe.rb reference-docs/b018-e18.pdf
#   bundle exec ruby scripts/ocr_transcribe.rb reference-docs/d011-e13.pdf --pages 1-50
#   bundle exec ruby scripts/ocr_transcribe.rb --all

require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"

API_URL = URI("https://api.z.ai/api/paas/v4/layout_parsing")
CACHE_DIR = File.join(File.dirname(__FILE__), "..", ".glm-ocr-cache")
API_KEY_FILE = File.expand_path("~/.zai-api-key")

PDF_TARGETS = [
  "reference-docs/b018-e18.pdf",
  "reference-docs/d036-e20.pdf",
  "reference-docs/d009-e04.pdf",
  "reference-docs/d011-e13.pdf",
  "reference-docs/r129-1-e20.pdf",
  "reference-docs/r129-2-e20.pdf",
  "reference-docs/r129-3-e20.pdf",
  "reference-docs/r129-4-e20.pdf",
].freeze

def load_api_key
  return ENV["Z_AI_API_KEY"] if ENV["Z_AI_API_KEY"] && !ENV["Z_AI_API_KEY"].empty?

  if File.exist?(API_KEY_FILE)
    lines = File.readlines(API_KEY_FILE).grep(/\A\s*export\s+Z_AI_API_KEY\s*=/)
    if lines.any?
      lines.first.match(/=['"]?([^'"\n]+)['"]?/)[1]
    else
      abort "ERROR: Could not find Z_AI_API_KEY in #{API_KEY_FILE}"
    end
  else
    abort "ERROR: No API key found. Set Z_AI_API_KEY or create #{API_KEY_FILE}"
  end
end

def cache_base(pdf_path)
  basename = File.basename(pdf_path, ".pdf")
  File.join(CACHE_DIR, basename)
end

def cached?(pdf_path)
  json_path = "#{cache_base(pdf_path)}.json"
  File.exist?(json_path) && File.size(json_path) > 100
end

def parse_page_range(arg)
  return nil unless arg

  if arg =~ /\A(\d+)-(\d+)\z/
    { start: $1.to_i, end: $2.to_i }
  elsif arg =~ /\A(\d+)\z/
    { start: $1.to_i, end: $1.to_i }
  else
    abort "ERROR: Invalid page range '#{arg}'. Use '1-50' or '51-86'."
  end
end

def transcribe(pdf_path, api_key, page_range: nil)
  pdf_full = File.expand_path(pdf_path)
  unless File.exist?(pdf_full)
    abort "ERROR: PDF not found: #{pdf_full}"
  end

  base = cache_base(pdf_path)
  json_path = "#{base}.json"
  md_path = "#{base}.md"

  if cached?(pdf_path) && !page_range
    puts "  Cached: #{json_path}"
    return
  end

  FileUtils.mkdir_p(CACHE_DIR)

  b64 = Base64.strict_encode64(File.binread(pdf_full))
  puts "  Base64 encoded #{File.size(pdf_full)} bytes (#{b64.length} chars)"

  body = {
    "model" => "glm-ocr",
    "file" => "data:application/pdf;base64,#{b64}",
  }
  body["start_page_id"] = page_range[:start] if page_range
  body["end_page_id"] = page_range[:end] if page_range

  puts "  Calling GLM-OCR API..."
  request = Net::HTTP::Post.new(API_URL.path, {
    "Authorization" => "Bearer #{api_key}",
    "Content-Type" => "application/json",
  })
  request.body = JSON.generate(body)

  http = Net::HTTP.new(API_URL.host, API_URL.port)
  http.use_ssl = true
  http.read_timeout = 300
  http.open_timeout = 30

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    abort "ERROR: API returned HTTP #{response.code}: #{response.body[0..500]}"
  end

  data = JSON.parse(response.body)

  # Handle page-range suffix for cache files
  suffix = page_range ? ".p#{page_range[:start]}-#{page_range[:end]}" : ""
  json_out = "#{base}#{suffix}.json"
  md_out = "#{base}#{suffix}.md"

  File.write(json_out, JSON.pretty_generate(data), encoding: "utf-8")
  puts "  Saved: #{json_out} (#{File.size(json_out)} bytes)"

  if data["md_results"]
    md_text = data["md_results"]
    File.write(md_out, md_text, encoding: "utf-8")
    puts "  Saved: #{md_out} (#{File.size(md_out)} bytes)"
  else
    puts "  WARNING: No md_results in response"
  end

  if data["usage"]
    puts "  Tokens: #{data.dig('usage', 'total_tokens')} (prompt: #{data.dig('usage', 'prompt_tokens')}, completion: #{data.dig('usage', 'completion_tokens')})"
  end
end

# Parse CLI args
if ARGV.empty?
  puts "Usage:"
  puts "  ruby scripts/ocr_transcribe.rb <pdf-path> [--pages N-M]"
  puts "  ruby scripts/ocr_transcribe.rb --all"
  exit 1
end

api_key = load_api_key

if ARGV[0] == "--all"
  puts "Transcribing all PDFs..."
  PDF_TARGETS.each do |pdf|
    puts "\n=== #{pdf} ==="
    transcribe(pdf, api_key)
  end
else
  pdf_path = ARGV[0]
  page_range = nil
  ARGV.each_with_index do |arg, i|
    if arg == "--pages" && ARGV[i + 1]
      page_range = parse_page_range(ARGV[i + 1])
    end
  end
  transcribe(pdf_path, api_key, page_range: page_range)
end

puts "\nDone."
