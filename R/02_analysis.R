# R/02_analysis.R
# Purpose: pull analysis_panel from DuckDB and estimate (Phase 9).
# Non-negotiables:
#   - survey weights on all means (survey::svydesign / svymean)
#   - standard errors CLUSTERED at country level (fixest ... cluster = ~country_id)
#   - report the balanced-panel version alongside the full panel
#   - DESCRIPTIVE only. Two-way FE on observational cross-country data does not
#     identify a causal effect. No causal language in output or comments.
# Must run end-to-end from a fresh clone and reproduce every number in docs/memo.md.
# STATUS: stub.

# library(DBI); library(duckdb); library(dplyr); library(survey); library(fixest)
