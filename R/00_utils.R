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
      repair_double_encoding(haven::read_sav(path, encoding = "latin1", ...))
    }
  )
}

# ---- repair_double_encoding -------------------------------------------------
# Merge6.sav is MIXED-encoded: it declares LATIN1, most of its text is really
# UTF-8, and a few verbatim fields are genuinely Latin-1. Reading the whole file
# as latin1 (the only way it reads at all) therefore DOUBLE-ENCODES the UTF-8
# parts: "Sao Tome and Principe" arrives as "SA£o TomA© and PrA-ncipe", which no
# longer matches docs/countries.csv and silently drops 1,196 respondents on the
# country join.
#
# The fix is exact and checkable: re-encode each string's code points back to
# Latin-1 bytes and reinterpret them as UTF-8. Applied ONLY where the result is
# valid UTF-8 and actually differs, so the genuinely Latin-1 verbatims are left
# untouched. Verified on this file: country labels and French/Portuguese
# verbatims are repaired, genuinely Latin-1 strings are preserved byte for byte.
.bytes <- function(v) vapply(v, function(s) paste(charToRaw(s), collapse = ""), character(1))

undouble <- function(x) {
  if (!length(x) || !is.character(x)) return(x)
  y <- suppressWarnings(iconv(x, from = "UTF-8", to = "latin1"))
  Encoding(y) <- "UTF-8"
  ok <- !is.na(y)
  ok[ok] <- validUTF8(y[ok])
  ok[ok] <- .bytes(y[ok]) != .bytes(x[ok])
  out <- x; out[ok] <- y[ok]; out
}

# Repair a whole data frame: character values, value-label names, variable labels.
repair_double_encoding <- function(df) {
  for (nm in names(df)) {
    col <- df[[nm]]
    if (is.character(col)) col[] <- undouble(as.character(col))
    labs <- attr(col, "labels", exact = TRUE)
    if (!is.null(labs) && !is.null(names(labs))) {
      names(labs) <- undouble(names(labs)); attr(col, "labels") <- labs
    }
    lb <- attr(col, "label", exact = TRUE)
    if (!is.null(lb)) attr(col, "label") <- undouble(as.character(lb))
    df[[nm]] <- col
  }
  df
}

# Which encoding actually worked -- recorded in the staging manifest so the
# quirk is documented rather than silently absorbed.
sav_encoding_used <- function(path) {
  ok <- tryCatch({ haven::read_sav(path, n_max = 0); TRUE }, error = function(e) FALSE)
  if (!ok) return("latin1")
  tryCatch({ haven::read_sav(path); "default" }, error = function(e) "latin1")
}
