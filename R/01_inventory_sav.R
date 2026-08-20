# R/01_inventory_sav.R  --  Phase 1.3 discovery
#
# Purpose: read metadata out of each .sav and write two inventories, so that
#          variable names and value labels are EXTRACTED rather than hand-typed.
#          The .sav is ground truth for what is IN the data; the codebook PDF is
#          documentation ABOUT it. Both are needed and they are cross-checked
#          against each other in 03_build_crosswalk.R.
#
# Writes (derived; gitignored):
#   docs/inventory_variables.csv   round, variable_name, variable_label, n_value_labels
#   docs/inventory_values.csv      round, variable_name, value_raw, value_label
#
# Usage: Rscript R/01_inventory_sav.R
#   RAW_DIR env var overrides the default data/raw location.

suppressPackageStartupMessages({
  library(haven); library(dplyr); library(purrr); library(readr); library(tibble)
})

RAW_DIR <- Sys.getenv("RAW_DIR", "data/raw")
OUT_DIR <- Sys.getenv("OUT_DIR", "docs")
ROUNDS  <- c(6L, 7L, 8L, 9L)
sav_path <- function(r) file.path(RAW_DIR, sprintf("Merge%d.sav", r))

# n_max = 1: we need the column attributes, not the rows. Reading a single row
# keeps haven's labelled attributes intact while staying fast on ~50MB files.
read_meta <- function(r) haven::read_sav(sav_path(r), n_max = 1)

inventory_variables <- function(df, round_number) {
  tibble(
    round_number   = round_number,
    variable_name  = names(df),
    variable_label = map_chr(df, function(x) {
      l <- attr(x, "label", exact = TRUE)
      if (is.null(l)) NA_character_ else as.character(l)[1]
    }),
    n_value_labels = map_int(df, function(x) {
      v <- attr(x, "labels", exact = TRUE)
      if (is.null(v)) 0L else length(v)
    })
  )
}

inventory_values <- function(df, round_number) {
  imap_dfr(df, function(col, nm) {
    labs <- attr(col, "labels", exact = TRUE)
    if (is.null(labs) || length(labs) == 0L) return(NULL)
    tibble(round_number = round_number, variable_name = nm,
           value_raw = as.numeric(unname(labs)), value_label = names(labs))
  })
}

message("Reading .sav metadata (one row each) ...")
metas <- map(ROUNDS, read_meta)
vars  <- map2_dfr(metas, ROUNDS, inventory_variables)
vals  <- map2_dfr(metas, ROUNDS, inventory_values)

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
write_csv(vars, file.path(OUT_DIR, "inventory_variables.csv"), na = "")
write_csv(vals, file.path(OUT_DIR, "inventory_values.csv"),    na = "")
message(sprintf("Wrote %d variable rows and %d value-label rows.", nrow(vars), nrow(vals)))

# ---- keyword search helper --------------------------------------------------
# Suggests candidate variables by wording. It does not decide: confirm every hit
# against the round's codebook before it enters the crosswalk.
find_var <- function(pattern) {
  vars %>%
    filter(grepl(pattern, variable_label, ignore.case = TRUE)) %>%
    arrange(variable_name, round_number) %>%
    print(n = 200)
}
#  find_var("tax") ; find_var("corrupt") ; find_var("handling")
