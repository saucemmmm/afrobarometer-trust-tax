# R/05_build_database.R  --  build the DuckDB database from the SQL files
#
# Purpose: execute sql/01-04 in order against data/afrobarometer.duckdb,
#          and print each script's verification output. One command rebuilds the
#          whole database from a fresh clone.
#
# Usage:  Rscript R/05_build_database.R            # from the REPOSITORY ROOT
#         Rscript R/05_build_database.R --fresh    # delete the .duckdb first
#
# Prerequisites: R/01, R/03 and R/04 must have run (they produce docs/*.csv and
# data/staging/*.parquet). The .duckdb file is gitignored and rebuilt from those.
#
# Why R rather than the DuckDB CLI: the duckdb R package is already required for
# Phase 9, so this adds no install, and it avoids the shell-redirection
# difference between bash (`duckdb db < file.sql`) and PowerShell, which has no
# `<` operator.

suppressPackageStartupMessages({ library(DBI); library(duckdb) })

DB_PATH <- Sys.getenv("DB_PATH", "data/afrobarometer.duckdb")
SCRIPTS <- c("sql/01_schema.sql",
             "sql/02_load_staging.sql",
             "sql/03_build_crosswalk.sql",
             "sql/04_normalize.sql",
             "sql/05_validate.sql",
             "sql/analysis/panel_country_round.sql",   # must precede the other three
             "sql/analysis/change_over_rounds.sql",
             "sql/analysis/rank_within_region.sql",
             "sql/analysis/coverage_report.sql")

# -----------------------------------------------------------------------------
# split_sql(): break a script into individual statements.
#
# Naive strsplit(sql, ";") is WRONG here and fails on this repo's own files:
# 02_load_staging.sql contains "ALL columns are kept;" inside a comment, which
# a naive split turns into a fragment that the parser rejects. This walks the
# string tracking single-quoted literals, -- line comments and /* */ blocks, and
# only splits on semicolons that are outside all three.
# -----------------------------------------------------------------------------
split_sql <- function(sql) {
  chars <- strsplit(sql, "", fixed = TRUE)[[1]]
  n <- length(chars); out <- character(0); buf <- character(0)
  in_str <- FALSE; in_line <- FALSE; in_block <- FALSE
  i <- 1L
  while (i <= n) {
    ch  <- chars[i]
    nxt <- if (i < n) chars[i + 1L] else ""
    if (in_line) {
      if (ch == "\n") in_line <- FALSE
      buf <- c(buf, ch); i <- i + 1L; next
    }
    if (in_block) {
      if (ch == "*" && nxt == "/") { in_block <- FALSE; buf <- c(buf, ch, nxt); i <- i + 2L; next }
      buf <- c(buf, ch); i <- i + 1L; next
    }
    if (in_str) {
      if (ch == "'" && nxt == "'") { buf <- c(buf, ch, nxt); i <- i + 2L; next }  # escaped quote
      if (ch == "'") in_str <- FALSE
      buf <- c(buf, ch); i <- i + 1L; next
    }
    if (ch == "-" && nxt == "-") { in_line  <- TRUE; buf <- c(buf, ch, nxt); i <- i + 2L; next }
    if (ch == "/" && nxt == "*") { in_block <- TRUE; buf <- c(buf, ch, nxt); i <- i + 2L; next }
    if (ch == "'")               { in_str   <- TRUE; buf <- c(buf, ch); i <- i + 1L; next }
    if (ch == ";") { out <- c(out, paste0(buf, collapse = "")); buf <- character(0); i <- i + 1L; next }
    buf <- c(buf, ch); i <- i + 1L
  }
  out <- c(out, paste0(buf, collapse = ""))
  # drop anything that is only whitespace and comments
  keep <- vapply(out, function(s) {
    s2 <- gsub("/\\*.*?\\*/", "", s)
    s2 <- gsub("(?m)--[^\n]*", "", s2, perl = TRUE)
    nzchar(trimws(s2))
  }, logical(1))
  trimws(out[keep])
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--fresh" %in% args && file.exists(DB_PATH)) {
    file.remove(DB_PATH)
    if (file.exists(paste0(DB_PATH, ".wal"))) file.remove(paste0(DB_PATH, ".wal"))
    message("Removed existing ", DB_PATH)
  }
  for (f in SCRIPTS) if (!file.exists(f)) stop("Missing ", f, " - run from the repository root.")

  dir.create(dirname(DB_PATH), showWarnings = FALSE, recursive = TRUE)
  con <- dbConnect(duckdb::duckdb(), DB_PATH)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  for (f in SCRIPTS) {
    stmts <- split_sql(readLines(f, warn = FALSE) |> paste(collapse = "\n"))
    message(sprintf("\n== %s  (%d statements)", f, length(stmts)))
    for (s in stmts) {
      is_select <- grepl("^\\s*(--[^\n]*\n\\s*)*(SELECT|WITH|FROM)", s, ignore.case = TRUE)
      res <- tryCatch(
        if (is_select) dbGetQuery(con, s) else { dbExecute(con, s); NULL },
        error = function(e)
          stop(sprintf("Failed in %s:\n%s\n\nStatement:\n%s",
                       f, conditionMessage(e), substr(s, 1, 400)), call. = FALSE))
      if (!is.null(res) && nrow(res)) { print(res, row.names = FALSE) }
    }
  }
  # Validation is a GATE, not a report. A build that fails its own checks must
  # not exit 0 and hand the user a database that looks finished.
  fails <- dbGetQuery(con, "SELECT * FROM core.validation_failures")
  if (nrow(fails)) {
    print(fails, row.names = FALSE)
    stop(sprintf("%d validation check(s) FAILED - see above. The database is built ",
                 nrow(fails)),
         "but must not be used for analysis until these are resolved.", call. = FALSE)
  }
  message("\nAll validation checks passed.")
  message("Database built: ", DB_PATH)
  message("Inspect it with:")
  message("  core.crosswalk_grid        concept x round variable-code drift")
  message("  core.validation_checks     all checks, including warnings")
  message("  core.missingness_report    item non-response by concept x round")
  message("  core.analysis_panel        country-round weighted means (R handoff)")
  message("  core.analysis_panel_balanced  countries present in all four rounds")
  message("  core.coverage_grid         country x round, NULLs included")
}

main()
