source "https://rubygems.org"

gem "metanorma-cli" #, github: "metanorma/metanorma-cli"
gem "mn2pdf", ">=2.52"
# the documents declare :mn-document-class: oiml; the cli in-document
# flavor detection loads the oiml flavor gem (unreleased — 0.1.0 is
# the first cut, W11 of the release graph)
gem "metanorma-oiml", github: "metanorma/metanorma-oiml", branch: "main"
gem "metanorma-taste", github: "metanorma/metanorma-taste", branch: "main"

# WARNING: only for testing
# gem "html2doc", github: "metanorma/html2doc", branch: "main"
# gem "isodoc-i18n", github: "metanorma/isodoc-i18n", branch: "main"
# gem "isodoc", github: "metanorma/isodoc", branch: "main"
# gem "metanorma-standoc", github: "metanorma/metanorma-standoc", branch: "main"
# gem "metanorma", git: "https://github.com/metanorma/metanorma", branch: "main"
# gem "metanorma-iso", github: "metanorma/metanorma-iso", branch: "main"
# gem "metanorma-taste", github: "metanorma/metanorma-taste", branch: "main"
# gem "metanorma-utils", github: "metanorma/metanorma-utils", branch: "main"
# gem "relaton-render", "= 3.0.0"
# #gem "fontist", github: "fontist/fontist", branch: "main"
# gem "mn2pdf"
# gem "debug"
# gem "sassc-embedded"
gem "relaton", "~> 3.0" # 3.0.1 carries the COW prune fix (relaton#392)
gem "relaton-bib", "2.2.0.pre.alpha.1"
gem "pubid", "~> 2.0" # 2.0.0 released; the git source now carries the 2.1 pre line
