# R/01_convert_sav.R
# Purpose: read the SPSS .sav merged round files and write one Parquet staging
#          file per round to data/staging/ (Phase 3).
# Critical: haven::read_sav() carries SPSS value labels as attributes. Capture
#           them BEFORE coercing to plain types — those labels are how responses
#           are decoded, and they are the thing most often silently discarded.
# Keeps ALL columns. Subsetting happens in SQL, not here.
# STATUS: stub.

# library(haven); library(dplyr); library(arrow)
