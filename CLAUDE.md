# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This is a Metanorma project that compiles OIML (International Organization of Legal Metrology) publications from AsciiDoc sources into HTML, PDF, XML, and other formats. Documents use the `metanorma-oiml` flavor (`:mn-document-class: oiml`).

## Build commands

```sh
# Install dependencies
bundle

# Build a single document
bundle exec metanorma sources/<doc-dir>/document.adoc

# Build a collection (multi-part documents)
bundle exec metanorma sources/r060/collection.yml
bundle exec metanorma sources/r138-e07/collection.yml

# Build the full site (all documents listed in metanorma.yml)
bundle exec metanorma site generate
```

Output goes to `sources/<doc-dir>/document.{html,pdf,xml}` for single documents, or `sources/<collection-dir>/collection-output/` for collections. Site generation creates `_site/`.

## Font prerequisites

PDF rendering requires "Futura PT Book", "Futura PT Demi", and "Futura PT Light" fonts from the private Metanorma Fontist repository:

```sh
fontist repo setup metanorma git@github.com:metanorma/fontist-formulas-private.git
fontist repo update metanorma
fontist install 'Futura PT Book'
fontist install 'Futura PT Demi'
fontist install 'Futura PT Light'
```

## Source structure

- `metanorma.yml` — site manifest listing all documents/collections to build
- `sources/<id>/document.adoc` — main AsciiDoc entry point for each document (e.g., `r060/1/`, `b022-e23/`)
- `sources/<id>/sections/` — included section files, assembled via `include::` directives in document.adoc
- `sources/<id>/images/` — images referenced from the AsciiDoc sources
- `sources/<id>/collection.yml` — Metanorma collection manifest for multi-part documents (r060, r138-e07, r144)
- `reference-docs/` — reference PDFs for comparison

Each `document.adoc` uses standard Metanorma AsciiDoc attributes (`:docidentifier:`, `:doctype:`, `:mn-document-class: oiml`, etc.) and includes sections from the `sections/` subdirectory.

## OIML document types

The doctypes used in this repo: `international-recommendation` (R), `international-basic-publication` (B), `international-document` (D), `international-guide` (G), `expert-report` (E).

## CI workflows

- `generate.yml` — builds using the `metanorma/metanorma` Docker image, publishes artifacts
- `docker.yml` — builds and deploys to GitHub Pages using the Docker image
- `generate-to-ghp.yml` — builds with native Ruby on Ubuntu, uses Firelight for HTML rendering of select documents, deploys to GitHub Pages
