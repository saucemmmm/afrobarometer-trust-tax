# R/02_parse_codebooks.R  --  Phase 1.3 codebook extraction
#
# Purpose: the codebook PDFs are rigidly structured -- every variable is an
#          entry of the form
#              Question Number: / Question: / Variable Label: /
#              Values: / Value Labels: / Source: / Note:
#          so they can be parsed rather than transcribed. Writes one row per
#          entry with the PDF PAGE it appears on, which becomes the
#          codebook_page audit trail in the crosswalk.
#
# Writes: docs/codebook_entries.csv  (~1,445 entries across rounds 6-9)
# Usage : Rscript R/02_parse_codebooks.R
#
# NOTE: page numbers are PDF pages (what a viewer's page box shows), NOT the
#       printed page numbers, which differ. State the convention when citing.

suppressPackageStartupMessages({
  library(pdftools); library(dplyr); library(purrr); library(readr)
  library(tibble); library(stringr)
})

RAW_DIR <- Sys.getenv("RAW_DIR", "data/raw")
OUT_DIR <- Sys.getenv("OUT_DIR", "docs")
ROUNDS  <- c(6L, 7L, 8L, 9L)
FIELDS  <- c("Question", "Variable Label", "Values", "Value Labels", "Source", "Note")

parse_round <- function(round_number) {
  path  <- file.path(RAW_DIR, sprintf("Merge%d_Codebook.pdf", round_number))
  pages <- pdftools::pdf_text(path)
  # strip the running footer so it does not bleed into the last field on a page
  pages <- str_replace_all(pages, "\\n?[ \\t]*Copyright Afrobarometer[ \\t]*\\d*[ \\t]*(?=\\n|$)", "")
  pages <- paste0(pages, "\n")

  ends   <- cumsum(nchar(pages))
  starts <- c(1L, head(ends, -1L) + 1L)
  page_of <- function(pos) which(pos >= starts & pos <= ends)[1]

  txt <- paste(pages, collapse = "")
  txt <- str_replace_all(txt, "-\\n", "")            # de-hyphenate line breaks

  hits <- str_locate_all(txt, "Question Number:[ \\t]*([^\\s\\n]+)")[[1]]
  if (nrow(hits) == 0L) return(tibble())
  qn <- str_match_all(txt, "Question Number:[ \\t]*([^\\s\\n]+)")[[1]][, 2]

  field_alt <- paste(str_replace_all(FIELDS, " ", "[ ]"), collapse = "|")

  map_dfr(seq_len(nrow(hits)), function(k) {
    chunk_start <- hits[k, "end"] + 1L
    chunk_end   <- if (k < nrow(hits)) hits[k + 1L, "start"] - 1L else nchar(txt)
    chunk <- substr(txt, chunk_start, chunk_end)
    vals <- map_chr(FIELDS, function(f) {
      pat <- sprintf("(?:^|\\n)[ \\t]*%s:[ \\t]*((?s).*?)(?=\\n[ \\t]*(?:%s):|$)",
                     str_replace_all(f, " ", "[ ]"), field_alt)
      m <- str_match(chunk, pat)
      if (is.na(m[1, 1])) return("")
      v <- str_squish(m[1, 2])
      # The final entry in each PDF runs on into the appendices (sample tables,
      # country code ranges, fieldwork notes). Cut there so the last variable's
      # Note field does not swallow 40kB of unrelated text.
      str_squish(str_split_fixed(v, "Appendix [0-9]", 2)[, 1])
    })
    out <- as_tibble(as.list(setNames(vals, tolower(gsub(" ", "_", FIELDS)))))
    bind_cols(tibble(round_number = round_number,
                     question_number = str_trim(qn[k]),
                     codebook_page = page_of(hits[k, "start"])), out)
  })
}

message("Parsing codebook PDFs ...")
entries <- map_dfr(ROUNDS, parse_round)
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
write_csv(entries, file.path(OUT_DIR, "codebook_entries.csv"), na = "")
message(sprintf("Parsed %d entries: %s", nrow(entries),
                paste(sprintf("R%d=%d", ROUNDS,
                              as.integer(table(factor(entries$round_number, ROUNDS)))),
                      collapse = ", ")))
