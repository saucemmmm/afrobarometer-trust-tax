# R/00_utils.R  --  shared helpers. Sourced by R/01, R/03 and R/04.

# ---- read_sav_safe ----------------------------------------------------------
# Merge6.sav DECLARES its encoding as LATIN1 in the file header, and contains
# Latin-1 bytes that are not valid UTF-8 -- e.g. row 39,619 of R6 has "VOTACAO"
# (with cedilla and tilde) in the verbatim field Q29B. haven's default read
# fails on it with "Unable to convert string to the requested encoding".
#
# Two things make this easy to miss:
#   * a truncated read (n_max = 1) succeeds, because the offending rows are
#     ~39k rows in;
#   * a col_select read succeeds, because only the selected columns are decoded.
# So R/01 and R/03 run clean on this file and R/04, which reads it whole, does
# not. Every .sav read in this project therefore goes through this helper.
read_sav_safe <- function(path, ...) {
  tryCatch(
    haven::read_sav(path, ...),
    error = function(e) {
      msg <- conditionMessage(e)
      if (!grepl("encoding|convert string", msg, ignore.case = TRUE)) stop(e)
      message(sprintf("  %s: default encoding failed; re-reading as latin1 ",
                      basename(path)),
              "(the file declares LATIN1 and carries non-UTF-8 bytes)")
      haven::read_sav(path, encoding = "latin1", ...)
    }
  )
}

# Which encoding actually worked -- recorded in the staging manifest so the
# quirk is documented rather than silently absorbed.
sav_encoding_used <- function(path) {
  ok <- tryCatch({ haven::read_sav(path, n_max = 0); TRUE }, error = function(e) FALSE)
  if (!ok) return("latin1")
  tryCatch({ haven::read_sav(path); "default" }, error = function(e) "latin1")
}
