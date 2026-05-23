#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrape the VIML (International Vocabulary of Legal Metrology) from
# http://viml.oiml.info and convert to a Glossarist v3 dataset.
#
# Phase 1: Download all HTML pages to disk (so we never re-scrape)
# Phase 2: Parse cached HTML and build Glossarist v3 dataset
#
# Usage:
#   bundle exec ruby scripts/scrape_viml.rb [COMMAND]
#
# Commands:
#   fetch    — download all pages to .viml-cache/ (default if no command)
#   build    — parse cached HTML, build Glossarist dataset
#   all      — fetch + build (default if cache is empty)

require "nokogiri"
require "net/http"
require "uri"
require "fileutils"

BASE_URL = "http://viml.oiml.info"
CACHE_DIR = File.join(File.dirname(__FILE__), "..", ".viml-cache")
OUTPUT_DIR = File.join(File.dirname(__FILE__), "..", "viml-glossarist")

DATASET_SOURCE = "urn:oiml:std:oiml:v:1:2022"

SECTION_NAMES = {
  "0" => "Basic terms",
  "1" => "Metrology and its legal aspects",
  "2" => "Legal metrology activities",
  "3" => "Documents and marks within legal metrology",
  "4" => "Classification of measuring instruments",
  "5" => "Construction and operation of measuring instruments",
  "6" => "Software in legal metrology",
  "A" => "Terms relating to conformity assessment",
}.freeze

TERM_IDS = [
  *("0.01".."0.15").to_a,
  *("1.01".."1.06").to_a,
  *("2.01".."2.24").to_a,
  *("3.01".."3.07").to_a,
  *("4.01".."4.16").to_a,
  *("5.01".."5.22").to_a,
  *("6.01".."6.08").to_a,
  *("A.1".."A.37").to_a,
].freeze

LANGUAGES = %w[en fr].freeze

# ═══════════════════════════════════════════════════════════════
# Phase 1: Fetch all pages to disk
# ═══════════════════════════════════════════════════════════════

def cache_path(lang, term_id)
  File.join(CACHE_DIR, lang, "#{term_id}.html")
end

def cached?(lang, term_id)
  File.exist?(cache_path(lang, term_id))
end

def fetch_all
  FileUtils.mkdir_p(CACHE_DIR)
  LANGUAGES.each { |l| FileUtils.mkdir_p(File.join(CACHE_DIR, l)) }

  total = TERM_IDS.size * LANGUAGES.size
  fetched = 0
  skipped = 0
  errors = []

  LANGUAGES.each do |lang|
    TERM_IDS.each do |term_id|
      dest = cache_path(lang, term_id)

      if File.exist?(dest) && File.size(dest) > 0
        skipped += 1
        next
      end

      url = "#{BASE_URL}/#{lang}/#{term_id}.html"
      fetched += 1
      printf("\r  [%d/%d] Fetching %-6s %s  ", fetched + skipped, total, lang, term_id)

      begin
        uri = URI.parse(url)
        resp = Net::HTTP.get_response(uri)

        unless resp.is_a?(Net::HTTPSuccess)
          errors << "#{url} => HTTP #{resp.code}"
          next
        end

        html = resp.body
        # Server sends ISO-8859-1 or mixed encoding for some French pages
        html = html.force_encoding("ISO-8859-1").encode("UTF-8")
        File.write(dest, html, encoding: "utf-8")
        sleep 0.3
      rescue => e
        errors << "#{url} => #{e.message}"
      end
    end
  end

  puts
  puts "  Fetched: #{fetched}, Cached: #{skipped}, Errors: #{errors.size}"
  errors.each { |e| puts "    ERROR: #{e}" } if errors.any?
  errors.empty?
end

# ═══════════════════════════════════════════════════════════════
# Phase 2: Parse cached HTML → Glossarist v3 dataset
# ═══════════════════════════════════════════════════════════════

require "glossarist"

TermData = Struct.new(
  :term_id, :term_name, :definition, :notes, :examples,
  :source_ref, :cross_refs, :language_code, :admitted_terms,
  keyword_init: true,
)

def load_cached(lang, term_id)
  path = cache_path(lang, term_id)
  return nil unless File.exist?(path)
  File.read(path, encoding: "utf-8")
end

def parse_term(html, term_id, lang)
  return nil unless html

  doc = Nokogiri::HTML(html, nil, "utf-8")
  content = doc.at_css('div[data-role="content"]')
  return nil unless content

  # Term name from h2.lemmatitle
  h2 = doc.at_css("h2.lemmatitle")
  term_name = h2 ? h2.text.strip.sub(/\A#{Regexp.escape(term_id)}\s*/, "") : nil

  # Admitted/alternative terms from div.lemmasubtitle
  admitted_terms = doc.css("div.lemmasubtitle").flat_map { |el|
    el.css("i, em").map(&:text).map(&:strip)
  }.reject(&:empty?)

  # Definition (some terms have multiple p.Definition paragraphs, e.g. 5.01)
  defn_nodes = content.css("p.Definition")
  definition_parts = []
  defn_xrefs = []
  defn_nodes.each do |node|
    text, xrefs = extract_text_with_xrefs(node)
    definition_parts << text
    defn_xrefs.concat(xrefs)
  end
  definition = definition_parts.join("\n")

  # Notes section
  notes_div = content.at_css("div#notes")
  raw_note_lines = []
  source_ref = nil
  cross_refs = defn_xrefs.dup

  if notes_div
    notes_div.css("p.NoteEx, p.Reference").each do |p|
      if p["class"] == "Reference"
        source_ref = parse_source_ref(p.text.strip)
        next
      end

      text, xrefs = extract_text_with_xrefs(p)
      cross_refs.concat(xrefs)
      raw_note_lines << text
    end
  end

  # Source ref outside notes div
  if !source_ref
    content.css("p.Reference").each do |p|
      source_ref = parse_source_ref(p.text.strip)
    end
  end

  # Footnotes outside content div
  doc.css("p.NoteEx").each do |p|
    next if content == p.parent || content.ancestors.include?(p.parent)
    next unless p.at_css("sup")
    text, xrefs = extract_text_with_xrefs(p)
    cross_refs.concat(xrefs)
    raw_note_lines << text
  end

  notes = group_notes(raw_note_lines)

  TermData.new(
    term_id: term_id,
    term_name: term_name,
    definition: definition,
    notes: notes,
    examples: [],
    source_ref: source_ref,
    cross_refs: cross_refs.uniq,
    language_code: lang == "en" ? "eng" : "fra",
    admitted_terms: admitted_terms,
  )
end

def extract_text_with_xrefs(node)
  return ["", []] unless node

  xrefs = []
  text_parts = []

  node.children.each do |child|
    case child
    when Nokogiri::XML::Text
      text_parts << child.text
    when Nokogiri::XML::Element
      span_class = child["class"].to_s
      if span_class.include?("Anchor")
        a = child.at_css("a")
        if a
          href = a["href"]&.sub(/\.html\z/, "")
          xrefs << href if href
          term_text = a.text.strip
          if term_text.empty?
            # Empty anchor link (e.g. A.5 -> A.4) — still record xref
          else
            text_parts << "{{#{term_text},#{href}}}"
          end
        end
      elsif child.name == "a" && (child.parent["class"].to_s.include?("Anchor"))
        href = child["href"]&.sub(/\.html\z/, "")
        xrefs << href if href
        term_text = child.text.strip
        text_parts << "{{#{term_text},#{href}}}"
      elsif child.name == "sup"
        text_parts << child.text
      elsif child.name == "br"
        text_parts << "\n"
      else
        inner_text, inner_xrefs = extract_text_with_xrefs(child)
        text_parts << inner_text
        xrefs.concat(inner_xrefs)
      end
    end
  end

  text = text_parts.join("").strip
  # Remove redundant "(see X.XX)" after concept mentions — the {{...}} handles the link
  text = text.gsub(/\s*\(see\s+[\dA]+\.\d+\)/, "")
  [text, xrefs]
end

def parse_source_ref(text)
  return nil unless text

  if text =~ /\A\[(.+?),\s*(.+?)\]\z/
    { ref: $1.strip, clause: $2.strip }
  elsif text =~ /\A\[(.+?)\]\z/
    { ref: $1.strip, clause: nil }
  end
end

def group_notes(raw_lines)
  return [] if raw_lines.empty?

  grouped = []
  current = nil

  raw_lines.each do |raw|
    stripped = raw.strip

    # Footnote: "1 some text"
    if stripped =~ /\A(\d+)\s+(.{2,})/
      grouped << $2.strip
      current = nil
      next
    end

    # "Note N to entry: ..."
    if stripped =~ /\ANote\s+\d+\s+to\s+entry:\s*(.+)/i
      current = $1.strip
      grouped << current
      next
    end

    # "Note N ..."
    if stripped =~ /\ANote\s+\d+\s+(.+)/i
      current = $1.strip
      grouped << current
      next
    end

    # "Note ..." (unnumbered single note)
    if stripped =~ /\ANote\s+(.+)/i && current.nil?
      current = $1.strip
      grouped << current
      next
    end

    # Bullet continuation
    if stripped.start_with?("·", "•", "-")
      bullet_text = stripped.sub(/[\A·•\-\s]+/, "")
      bullet_line = "— #{bullet_text}"
      if current
        current << "\n#{bullet_line}"
      else
        grouped << bullet_line unless bullet_text.empty?
        current = bullet_line
      end
      next
    end

    # Other continuation or standalone
    if current && !stripped.empty?
      current << "\n#{stripped}"
    elsif !stripped.empty?
      grouped << stripped
      current = grouped.last
    end
  end

  grouped
end

# ── Glossarist v3 object construction (following iev gem patterns) ──

def section_for(term_id)
  term_id[/\A([0-9A]+)/, 1]
end

def build_source(source_ref)
  return nil unless source_ref

  origin = Glossarist::Citation.new(
    ref: Glossarist::Citation::Ref.new(source: source_ref[:ref]),
    locality: source_ref[:clause] ? Glossarist::Locality.new(
      type: "clause",
      reference_from: source_ref[:clause],
    ) : nil,
  )

  Glossarist::ConceptSource.new(
    type: "authoritative",
    origin: origin,
  )
end

def build_localized_concept(data)
  cd = Glossarist::ConceptData.new
  cd.id = "#{data.term_id}-#{data.language_code}"
  cd.language_code = data.language_code

  cd.dates = [
    Glossarist::ConceptDate.new(type: "accepted", date: DateTime.parse("2022-01-01")),
  ]

  if data.definition && !data.definition.empty?
    cd.definition = [Glossarist::DetailedDefinition.new(content: data.definition)]
  end

  cd.notes = data.notes.map { |n| Glossarist::DetailedDefinition.new(content: n) }
  cd.examples = []

  if data.source_ref
    cd.sources = [build_source(data.source_ref)]
  end

  cd.terms = [
    Glossarist::Designation::Expression.new(
      designation: data.term_name,
      normative_status: "preferred",
    ),
  ]

  (data.admitted_terms || []).each do |alt|
    cd.terms << Glossarist::Designation::Expression.new(
      designation: alt,
      normative_status: "admitted",
    )
  end

  l10n = Glossarist::LocalizedConcept.new
  l10n.data = cd
  l10n.entry_status = "valid"
  l10n
end

def build_managed_concept(term_id, eng_data, fra_data, all_cross_refs)
  mc = Glossarist::ManagedConcept.new(data: { "id" => term_id })
  mc.schema_version = "3"

  # Domain (section classification)
  mc.data.domains = [
    Glossarist::ConceptReference.new(
      source: DATASET_SOURCE,
      concept_id: "section-#{section_for(term_id)}",
      ref_type: "domain",
    ),
  ]

  # Sources at managed concept level
  if eng_data&.source_ref
    mc.data.sources = [build_source(eng_data.source_ref)]
  end

  # Localizations
  mc.add_l10n(build_localized_concept(eng_data)) if eng_data
  mc.add_l10n(build_localized_concept(fra_data)) if fra_data

  # Cross-references (filter out self-references)
  mc.related = all_cross_refs.reject { |id| id == term_id }.map do |xref_id|
    Glossarist::RelatedConcept.new(
      type: "see",
      ref: Glossarist::ConceptRef.new(source: DATASET_SOURCE, id: xref_id),
    )
  end

  mc.status = "valid"
  mc
end

# ── Build pipeline ──

def build_all
  require "glossarist"

  puts "Parsing cached HTML files..."

  collection = Glossarist::ManagedConceptCollection.new
  errors = []

  TERM_IDS.each_with_index do |term_id, idx|
    printf("[%3d/%d] %s ", idx + 1, TERM_IDS.size, term_id)

    begin
      en_html = load_cached("en", term_id)
      fr_html = load_cached("fr", term_id)

      unless en_html
        puts "SKIP (no English HTML cached)"
        errors << "#{term_id}: no cached English page"
        next
      end

      en_data = parse_term(en_html, term_id, "en")
      fr_data = parse_term(fr_html, term_id, "fr")

      unless en_data
        puts "SKIP (parse failed)"
        errors << "#{term_id}: English parse failed"
        next
      end

      all_xrefs = (en_data.cross_refs + (fr_data&.cross_refs || [])).uniq
      concept = build_managed_concept(term_id, en_data, fr_data, all_xrefs)
      collection.store(concept)

      lang = fr_data ? "EN+FR" : "EN"
      notes = en_data.notes.size
      xrefs = all_xrefs.size
      src = en_data.source_ref ? "[#{en_data.source_ref[:ref]}]" : ""
      puts "OK #{lang} (#{notes}n, #{xrefs}x) #{src}"
    rescue => e
      puts "ERROR: #{e.message}"
      errors << "#{term_id}: #{e.message}"
    end
  end

  puts
  puts "Saving #{collection.managed_concepts.size} concepts to #{OUTPUT_DIR}..."
  FileUtils.mkdir_p(OUTPUT_DIR)

  # One YAML file per concept, named by concept ID (e.g., 0.05.yaml)
  # Each file is multi-document YAML: concept + localizations
  concept_ids = []
  collection.managed_concepts.each do |mc|
    doc = Glossarist::ConceptDocument.from_managed_concept(mc)
    filename = File.join(OUTPUT_DIR, "#{mc.data.id}.yaml")
    File.write(filename, doc.to_yamls, encoding: "utf-8")
    concept_ids << mc.data.id
  end

  # Generate register.yaml
  register_data = {
    "schema_version" => "3",
    "concepts" => concept_ids.sort_by { |id|
      parts = id.split(/(\d+)/).reject(&:empty?)
      parts.map { |p| p =~ /\A\d+\z/ ? p.to_i : p }
    },
  }
  File.write(File.join(OUTPUT_DIR, "register.yaml"), YAML.dump(register_data), encoding: "utf-8")

  puts "Done! #{collection.managed_concepts.size} concepts saved to #{OUTPUT_DIR}/."
  if errors.any?
    puts "Errors (#{errors.size}):"
    errors.each { |e| puts "  #{e}" }
  end
end

# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════

command = ARGV[0]

case command
when "fetch"
  puts "Phase 1: Fetching all VIML pages..."
  fetch_all
when "build"
  puts "Phase 2: Building Glossarist dataset from cache..."
  build_all
else
  # Auto-detect: fetch if cache is empty, then build
  cached_count = LANGUAGES.sum { |l| TERM_IDS.count { |t| cached?(l, t) } }
  if cached_count < TERM_IDS.size * LANGUAGES.size
    puts "Phase 1: Fetching all VIML pages (#{cached_count}/#{TERM_IDS.size * LANGUAGES.size} cached)..."
    fetch_all
    puts
  else
    puts "All #{cached_count} pages already cached."
  end
  puts "Phase 2: Building Glossarist dataset..."
  build_all
end
