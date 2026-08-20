# R/04_convert_sav.R  --  Phase 3: .sav -> Parquet staging
#
# Purpose: convert each merged SPSS round into a typed Parquet staging file for
#          DuckDB. Keeps ALL columns: subsetting happens later in SQL, so the
#          column-selection logic lives in version-controlled queries rather
#          than in a one-off script.
#
# Writes:  data/staging/r{6,7,8,9}.parquet   (gitignored; rebuilt from raw)
# Usage:   Rscript R/04_convert_sav.R
#
# LABELS ARE STRIPPED HERE, DELIBERATELY. haven carries SPSS value labels as
# attributes, and they are the thing most people accidentally discard. They are
# not discarded: R/01_inventory_sav.R has already captured every variable label
# and value label, and R/03_build_crosswalk.R has frozen the decisions into
# docs/crosswalk_values.csv. Staging therefore holds RAW CODES ONLY, and
# decoding happens by joining core.response_values. Run R/01 before this script.
#
# Parquet is written through the duckdb R package rather than arrow: duckdb is
# already required for Phase 9, so this adds no new dependency, and it keeps the
# staging writer and the database reader on the same type system.

suppressPackageStartupMessages({
  library(haven); library(dplyr); library(purrr); library(DBI); library(duckdb)
})

RAW_DIR     <- Sys.getenv("RAW_DIR",     "data/raw")
STAGING_DIR <- Sys.getenv("STAGING_DIR", "data/staging")
ROUNDS      <- c(6L, 7L, 8L, 9L)

# Published respondent counts, for the Phase 3 reconciliation check.
EXPECTED_N <- c(`6` = 53935L, `7` = 45823L, `8` = 48084L, `9` = 53444L)

# Identifier variables whose LABEL, not their code, is the stable key. Country
# numeric codes are round-specific (the codebook appendices assign each country
# a different code range per round), so the code cannot join across rounds. The
# name can -- via core.country_aliases, which absorbs the spelling drift. Both
# are kept: the raw code for provenance, the label for the join.
LABEL_ALSO_AS_TEXT <- c("COUNTRY", "REGION")

dir.create(STAGING_DIR, showWarnings = FALSE, recursive = TRUE)

# haven_labelled columns cannot be written directly. zap_labels() drops the
# value labels, zap_formats()/zap_widths() drop SPSS display attributes; the
# underlying codes are untouched.
strip_spss <- function(df) {
  df %>%
    haven::zap_labels() %>%
    haven::zap_formats() %>%
    haven::zap_widths() %>%
    mutate(across(where(is.labelled), as.numeric)) %>%
    # SPSS time-of-day fields arrive as hms/difftime, which the Parquet writer
    # does not accept. They are interview timestamps, not analysis variables.
    mutate(across(where(~ inherits(.x, "difftime")), as.character)) %>%
    as.data.frame()
}

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

manifest <- map_dfr(ROUNDS, function(r) {
  src <- file.path(RAW_DIR, sprintf("Merge%d.sav", r))
  out <- file.path(STAGING_DIR, sprintf("r%d.parquet", r))
  message(sprintf("R%d: reading %s ...", r, basename(src)))

  raw <- haven::read_sav(src)
  labels_as_text <- intersect(LABEL_ALSO_AS_TEXT, names(raw))
  extra <- as.data.frame(lapply(raw[labels_as_text],
                                function(x) as.character(haven::as_factor(x))))
  names(extra) <- paste0(labels_as_text, "_LABEL")
  df <- cbind(strip_spss(raw), extra)

  duckdb::duckdb_register(con, "tmp_round", df)
  dbExecute(con, sprintf("COPY tmp_round TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", out))
  duckdb::duckdb_unregister(con, "tmp_round")

  tibble::tibble(round_number = r, n_rows = nrow(df), n_cols = ncol(df),
                 expected_n = unname(EXPECTED_N[as.character(r)]),
                 parquet_mb = round(file.size(out) / 1024^2, 1))
})

manifest <- manifest %>% mutate(reconciles = n_rows == expected_n)
readr::write_csv(manifest, file.path("docs", "staging_manifest.csv"))
print(as.data.frame(manifest))

if (!all(manifest$reconciles)) {
  stop("Row counts do not reconcile against the published figures - investigate ",
       "before proceeding to sql/02_load_staging.sql")
}
message("All rounds reconcile. Staging written to ", STAGING_DIR)
