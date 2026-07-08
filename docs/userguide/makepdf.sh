#!/bin/bash

# Pin PDF timestamps (/CreationDate, /ModDate, /ID) so a rebuild from unchanged
# source is byte-identical to the CI build (#115). Keep in sync with the
# pre_compile export in .github/workflows/docs-pdf.yml.
export SOURCE_DATE_EPOCH=1700000000
export FORCE_SOURCE_DATE=1

pdflatex ADiGatorUserGuide.tex
bibtex ADiGatorUserGuide
pdflatex ADiGatorUserGuide.tex
pdflatex ADiGatorUserGuide.tex
rm *.log *.toc *.out *.bbl *.blg *.aux
# PDF is left in place alongside the source (docs/userguide/).