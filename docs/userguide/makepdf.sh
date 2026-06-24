#!/bin/bash

pdflatex ADiGatorUserGuide.tex
bibtex ADiGatorUserGuide
pdflatex ADiGatorUserGuide.tex
pdflatex ADiGatorUserGuide.tex
rm *.log *.toc *.out *.bbl *.blg *.aux
# PDF is left in place alongside the source (docs/userguide/).