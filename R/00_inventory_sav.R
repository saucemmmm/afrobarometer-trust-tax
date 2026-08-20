# R/00_inventory_sav.R
# Purpose: DISCOVERY ONLY (Phase 1.3 support). Reads metadata out of each .sav
#          and writes two inventories so that variable names and value labels
#          are EXTRACTED, not hand-transcribed. Hand-typing value labels invites
#          typos; the .sav is the ground truth for what is actually in the data,
#          and the codebook PDF is documentation of it.
#
# Writes (both gitignored -- they are derived, not source):
#   docs/inventory_variables.csv   round, variable_name, variable_label, n_value_labels
#   docs/inventory_values.csv      round, variable_name, value_raw, value_label
#
# This script does NOT decide anything. It changes no frozen list. It only tells
# you which variables exist in which round and what their labels say.
#
# Usage:  Rscript R/00_inventory_sav.R
#         then: search inventory_variables.csv for wording keywords, and confirm
#         each hit against the round's codebook page before it enters the crosswalk.

setwd("C:/Users/maxjd/dev/afrobarometer-trust-tax")


library(haven)
library(dplyr)
library(purrr)
library(readr)
library(tibble)

rounds <- tibble::tribble(
  ~round_number, ~path,
  6L, "data/raw/Merge6.sav",
  7L, "data/raw/Merge7.sav",
  8L, "data/raw/Merge8.sav",
  9L, "data/raw/Merge9.sav"
)

# n_max = 1: we need the column attributes, not the data. Reading one row keeps
# haven's labelled attributes intact while staying fast on ~50MB files.
read_meta <- function(path) haven::read_sav(path, n_max = 1)

inventory_variables <- function(df, round_number) {
  tibble(
    round_number   = round_number,
    variable_name  = names(df),
    variable_label = map_chr(df, ~ {
      l <- attr(.x, "label"); if (is.null(l)) NA_character_ else as.character(l)
    }),
    n_value_labels = map_int(df, ~ {
      v <- attr(.x, "labels"); if (is.null(v)) 0L else length(v)
    })
  )
}

inventory_values <- function(df, round_number) {
  imap_dfr(df, function(col, nm) {
    labs <- attr(col, "labels")
    if (is.null(labs) || !length(labs)) return(NULL)
    tibble(
      round_number  = round_number,
      variable_name = nm,
      value_raw     = as.numeric(unname(labs)),
      value_label   = names(labs)
    )
  })
}

message("Reading .sav metadata (one row each)...")
meta <- rounds %>%
  mutate(df = map(path, read_meta))

vars <- map2_dfr(meta$df, meta$round_number, inventory_variables)
vals <- map2_dfr(meta$df, meta$round_number, inventory_values)

dir.create("docs", showWarnings = FALSE)
write_csv(vars, "docs/inventory_variables.csv", na = "")
write_csv(vals, "docs/inventory_values.csv",    na = "")

message(sprintf("Wrote %d variable rows and %d value-label rows.", nrow(vars), nrow(vals)))

# ---- keyword search helper -------------------------------------------------
# Finds candidate variables by wording. Confirm every hit against the codebook
# before it enters docs/crosswalk_variables.csv. This suggests; it does not decide.
find_var <- function(pattern) {
  vars %>%
    filter(grepl(pattern, variable_label, ignore.case = TRUE)) %>%
    arrange(variable_name, round_number) %>%
    print(n = 200)
}

# Suggested starting searches for the Phase 0 frozen list:
  find_var("tax")
#   find_var("corrupt")
#   find_var("handling|performance")
#   find_var("econom")
#   find_var("weight|wt")
