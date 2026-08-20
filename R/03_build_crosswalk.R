# R/03_build_crosswalk.R  --  Phase 1.3 / Phase 5 crosswalk construction
#
# Purpose: build every artifact the normalized load depends on, from three
#          sources that are cross-checked against each other:
#            1. the frozen concept definitions below  (docs/question.md)
#            2. docs/inventory_*.csv                  (R/01, from the .sav)
#            3. docs/codebook_entries.csv             (R/02, from the PDFs)
#
# Writes:
#   docs/crosswalk_variables.csv   concept x round   -> core.question_map
#   docs/crosswalk_values.csv      concept x round x value_raw -> core.response_values
#   docs/countries.csv             canonical country + region  -> core.countries
#   docs/country_aliases.csv       raw COUNTRY string -> country_id
#   docs/coverage_by_item.csv      derived asked_all_countries
#
# Usage: Rscript R/03_build_crosswalk.R
#   Run R/01 and R/02 first. Reads full data for the coverage step (~1 min).

suppressPackageStartupMessages({
  library(haven); library(dplyr); library(purrr); library(readr)
  library(tibble); library(stringr); library(tidyr); library(stringi)
})

RAW_DIR <- Sys.getenv("RAW_DIR", "data/raw")
OUT_DIR <- Sys.getenv("OUT_DIR", "docs")
ROUNDS  <- c(6L, 7L, 8L, 9L)

# =============================================================================
# 1. FROZEN CONCEPT DEFINITIONS  --  see docs/question.md 6.1 and 7.
#    Changing anything here changes the frozen variable list. Do not edit
#    casually; the freeze is the point.
# =============================================================================
concepts <- tribble(
  ~canonical_code,             ~concept,               ~role,                ~scale,          ~higher_means,                 ~lo, ~hi,
  "trust_police",              "institutional_trust",  "outcome_component",  "likert_0_3",    "more trust",                   0L,  3L,
  "trust_courts",              "institutional_trust",  "outcome_component",  "likert_0_3",    "more trust",                   0L,  3L,
  "corruption_govt_officials", "corruption_perception","covariate",          "likert_0_3",    "more perceived corruption",    0L,  3L,
  "govt_perf_economy",         "govt_performance",     "covariate",          "likert_1_4",    "better perceived performance", 1L,  4L,
  "urban_rural",               "demographic",          "demographic",        "categorical",   "n/a (1=Urban, 2=Rural)",       NA,  NA,
  "age",                       "demographic",          "demographic",        "numeric",       "older",                        NA,  NA,
  "gender",                    "demographic",          "demographic",        "categorical",   "n/a (1=Male, 2=Female)",       1L,  2L,
  "education_level",           "demographic",          "demographic",        "ordinal_0_9",   "more education",               0L,  9L,
  "lived_poverty",             "material_deprivation", "control",            "continuous_0_4","more deprivation",             NA,  NA,
  "within_weight",             "survey_design",        "weight",             "continuous",    "n/a",                          NA,  NA,
  "trust_tax_authority",       "institutional_trust",  "extension",          "likert_0_3",    "more trust",                   0L,  3L,
  "corruption_tax_officials",  "corruption_perception","extension",          "likert_0_3",    "more perceived corruption",    0L,  3L,
  "lp_food",                   "material_deprivation", "lpi_component",      "likert_0_4",    "more deprivation",             0L,  4L,
  "lp_water",                  "material_deprivation", "lpi_component",      "likert_0_4",    "more deprivation",             0L,  4L,
  "lp_medical",                "material_deprivation", "lpi_component",      "likert_0_4",    "more deprivation",             0L,  4L,
  "lp_fuel",                   "material_deprivation", "lpi_component",      "likert_0_4",    "more deprivation",             0L,  4L,
  "lp_cash",                   "material_deprivation", "lpi_component",      "likert_0_4",    "more deprivation",             0L,  4L
)

# Round-specific variable names. NA = item not asked that round -- an explicit
# fact, recorded as a present = FALSE row rather than an absent row.
varmap <- tribble(
  ~canonical_code,             ~`6`,      ~`7`,      ~`8`,          ~`9`,
  "trust_police",              "Q52H",    "Q43G",    "Q41G",        "Q37G",
  "trust_courts",              "Q52J",    "Q43I",    "Q41I",        "Q37I",
  "corruption_govt_officials", "Q53C",    "Q44C",    "Q42C",        "Q38C",
  "govt_perf_economy",         "Q66A",    "Q56A",    "Q50A",        "Q46A",
  "urban_rural",               "URBRUR",  "URBRUR",  "URBRUR",      "URBRUR",
  "age",                       "Q1",      "Q1",      "Q1",          "Q1",
  "gender",                    "Q101",    "Q101",    "Q101",        "Q100",
  "education_level",           "Q97",     "Q97",     "Q97",         "Q94",
  "lived_poverty",             NA,        "LivedPoverty","LivedPoverty","LivedPoverty",
  "within_weight",             "withinwt","withinwt","withinwt_ea", "withinwt_ea",
  "trust_tax_authority",       "Q52D",    NA,        "Q41J",        NA,
  "corruption_tax_officials",  "Q53F",    NA,        "Q42G",        "Q38G",
  "lp_food",                   "Q8A",     "Q8A",     "Q7A",         "Q6A",
  "lp_water",                  "Q8B",     "Q8B",     "Q7B",         "Q6B",
  "lp_medical",                "Q8C",     "Q8C",     "Q7C",         "Q6C",
  "lp_fuel",                   "Q8D",     "Q8D",     "Q7D",         "Q6D",
  "lp_cash",                   "Q8E",     "Q8E",     "Q7E",         "Q6E"
) %>% pivot_longer(-canonical_code, names_to = "round_number",
                   values_to = "round_variable") %>%
      mutate(round_number = as.integer(round_number))

# Country name harmonization. NO non-ASCII literals appear below: an accented
# string in a source file is read differently depending on the R session's
# locale, which silently produced a 43rd country on the first run of this
# script. Instead, names are folded to an ASCII key, which collapses diacritic
# variants automatically ("Cote d'Ivoire" / "C<accent>te d'Ivoire"), and the
# canonical spelling is taken from the MOST RECENT round in which the country
# appears. Only genuine renames need an explicit entry, and both happen to be
# pure ASCII:
#   Cape Verde -> Cabo Verde   (2013 official renaming)
#   Swaziland  -> Eswatini     (2018 political RENAME; no string-similarity
#                               rule recovers this, and a naive name join
#                               splits Eswatini into two countries)
ascii_key <- function(x) {
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  tolower(gsub("[^A-Za-z]", "", x))
}
COUNTRY_RENAME <- c(capeverde = "caboverde", swaziland = "eswatini")

# The corruption battery's 0 category has an EMPTY label in every .sav.
# Confirmed as "None" from the codebooks; supplied here because it cannot be
# extracted.
CORRUPTION_ZERO <- c("corruption_govt_officials", "corruption_tax_officials")

inv_v <- read_csv(file.path(OUT_DIR, "inventory_variables.csv"), show_col_types = FALSE)
inv_l <- read_csv(file.path(OUT_DIR, "inventory_values.csv"),    show_col_types = FALSE)
cb    <- read_csv(file.path(OUT_DIR, "codebook_entries.csv"),    show_col_types = FALSE) %>%
         mutate(qn = str_to_upper(str_trim(question_number))) %>%
         distinct(round_number, qn, .keep_all = TRUE)

# =============================================================================
# 2. VALUES  --  one row per concept x round x raw code
#    A code is MISSING when it falls outside the concept's substantive range.
#    This is deliberately per-item: on education_level 9 = "Post-graduate" is
#    VALID while 98/99 are missing, so no code-invariant rule is safe.
# =============================================================================
URBAN_CODES <- c(1L, 3L, 460L)   # Urban, Semi-Urban/Peri-urban, and the
RURAL_CODES <- c(2L)             # undocumented 460 found in R6/R7 data

values <- varmap %>%
  filter(!is.na(round_variable)) %>%
  left_join(concepts, by = "canonical_code") %>%
  inner_join(inv_l, by = c("round_number", "round_variable" = "variable_name")) %>%
  mutate(
    value_raw   = as.integer(value_raw),
    value_label = if_else(canonical_code %in% CORRUPTION_ZERO & value_raw == 0L &
                            (is.na(value_label) | value_label %in% c("", "nan")),
                          "None", value_label),
    is_missing = if_else(
      canonical_code == "urban_rural",
      !(value_raw %in% c(URBAN_CODES, RURAL_CODES)),
      is.na(lo) | value_raw < lo | value_raw > hi),
    value_harmonized = case_when(
      is_missing                                            ~ NA_integer_,
      canonical_code == "urban_rural" & value_raw %in% URBAN_CODES ~ 1L,
      canonical_code == "urban_rural"                       ~ 2L,
      TRUE                                                  ~ value_raw),
    harmonization_rule = case_when(
      is_missing                      ~ "missing",
      canonical_code == "urban_rural" ~ "collapsed to binary: urban={1,3,460}, rural={2}",
      TRUE                            ~ "direct"),
    notes = NA_character_
  ) %>%
  select(canonical_code, round_number, value_raw, value_label,
         value_harmonized, is_missing, harmonization_rule, notes) %>%
  arrange(canonical_code, round_number, value_raw)

# =============================================================================
# 3. COVERAGE  --  derive asked_all_countries from the DATA, not the Note field.
#    The Note records intent; the data records what happened. An item counts as
#    not asked in a country when that country has zero valid responses.
# =============================================================================
message("Deriving country coverage from the data ...")
coverage <- map_dfr(ROUNDS, function(r) {
  vm <- varmap %>% filter(round_number == r, !is.na(round_variable)) %>%
        left_join(concepts, by = "canonical_code") %>%
        filter(role != "weight", canonical_code != "lived_poverty")
  cols <- unique(c(vm$round_variable, "COUNTRY"))
  df   <- haven::read_sav(file.path(RAW_DIR, sprintf("Merge%d.sav", r)), col_select = all_of(cols))
  cty  <- as.character(haven::as_factor(df$COUNTRY))
  map_dfr(seq_len(nrow(vm)), function(i) {
    cc <- vm$canonical_code[i]
    vr <- values %>% filter(canonical_code == cc, round_number == r)
    x  <- as.numeric(df[[vm$round_variable[i]]])
    ok <- vr$value_raw[!vr$is_missing]
    valid <- if (length(ok)) x %in% ok else (!is.na(x) & !(x %in% vr$value_raw[vr$is_missing]))
    zero <- names(which(tapply(valid, cty, sum, na.rm = TRUE) == 0))
    tibble(canonical_code = cc, round_number = r,
           asked_all_countries = length(zero) == 0,
           countries_excluded  = paste(sort(zero), collapse = "; "))
  })
})

# =============================================================================
# 4. VARIABLES  --  concept x round, with codebook fields merged in.
#    The codebook is authoritative for wording, page, source and note.
# =============================================================================
variables <- varmap %>%
  left_join(concepts, by = "canonical_code") %>%
  mutate(present = !is.na(round_variable), qn = str_to_upper(round_variable)) %>%
  left_join(cb %>% select(round_number, qn, codebook_page,
                          question, source, note), by = c("round_number", "qn")) %>%
  left_join(coverage, by = c("canonical_code", "round_number")) %>%
  left_join(values %>% filter(!is_missing) %>%
              count(canonical_code, round_number, name = "n_substantive_categories"),
            by = c("canonical_code", "round_number")) %>%
  left_join(inv_v %>% select(round_number, variable_name, variable_label),
            by = c("round_number", "round_variable" = "variable_name")) %>%
  transmute(
    canonical_code, concept, role, round_number, present,
    round_variable  = coalesce(round_variable, ""),
    variable_label  = coalesce(variable_label, ""),
    question_text   = coalesce(question, ""),
    codebook_source = coalesce(source, ""),
    codebook_note   = coalesce(note, ""),
    codebook_page,
    raw_scale_type  = if_else(present, scale, ""),
    n_substantive_categories,
    higher_means,
    asked_all_countries, countries_excluded,
    # An absent row is verified: it records a CONFIRMED absence. Leaving it
    # FALSE would conflate "checked, not asked" with "not yet checked".
    verified = !present | nzchar(coalesce(question, "")) |
               canonical_code %in% c("lived_poverty", "within_weight"),
    notes = case_when(
      !present & canonical_code == "lived_poverty" ~
        "constructed from lp_* components; see docs/question.md 6.3",
      !present ~ "item not asked in this round",
      canonical_code %in% c("lived_poverty", "within_weight") ~
        "constructed/design variable; no codebook question exists",
      role == "lpi_component" & round_number %in% c(8L, 9L) ~
        "stem wording differs from R6/R7: 'gone without' moved into the stem",
      TRUE ~ "")
  ) %>%
  arrange(match(canonical_code, concepts$canonical_code), round_number)

# =============================================================================
# 5. COUNTRIES  --  canonical names, aliases and region
# =============================================================================
message("Building country tables ...")
ctry <- map_dfr(ROUNDS, function(r) {
  cols <- c("COUNTRY", if (r != 8L) "COUNTRY.BY.REGION")
  df <- haven::read_sav(file.path(RAW_DIR, sprintf("Merge%d.sav", r)), col_select = all_of(cols))
  tibble(country_name_raw = as.character(haven::as_factor(df$COUNTRY)),
         region = if (r != 8L) as.character(haven::as_factor(df[["COUNTRY.BY.REGION"]])) else NA_character_,
         round_number = r) %>% distinct()
})
ctry <- ctry %>%
  mutate(k = ascii_key(country_name_raw),
         k = coalesce(unname(COUNTRY_RENAME[k]), k))

# canonical spelling = the one used in the most recent round the country appears in
canon_name <- ctry %>%
  arrange(k, desc(round_number)) %>%
  group_by(k) %>% summarise(country_name = first(country_name_raw), .groups = "drop")

# Afrobarometer's own region assignment is not constant: Madagascar and
# Mauritius move from Southern Africa (R6/R7) to East Africa (R9). `region` is
# one value per country in the schema, so we take the MOST RECENT
# classification -- the same rule used for the canonical name. A FIXED region is
# also the right choice for the within-region RANK query: if the peer group
# moved between rounds, a change in rank could not be attributed to the country
# rather than to the regrouping.
region_changes <- ctry %>% filter(!is.na(region)) %>%
  distinct(k, round_number, region) %>% count(k, region) %>%
  count(k, name = "n_regions") %>% filter(n_regions > 1)

countries <- ctry %>%
  left_join(canon_name, by = "k") %>%
  filter(!is.na(region)) %>%
  arrange(k, desc(round_number)) %>%
  group_by(k, country_name) %>%
  summarise(region = first(region), .groups = "drop") %>%
  arrange(country_name) %>%
  mutate(country_id = row_number(), iso3 = NA_character_) %>%
  select(country_id, country_name, iso3, region)

country_aliases <- ctry %>%
  distinct(country_name_raw, k) %>%
  left_join(canon_name, by = "k") %>%
  left_join(countries %>% select(country_id, country_name), by = "country_name") %>%
  mutate(is_alias = country_name_raw != country_name) %>%
  arrange(country_name_raw) %>%
  select(country_name_raw, country_id, country_name, is_alias)

# =============================================================================
# 6. WRITE + VALIDATE
# =============================================================================
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
write_csv(variables,       file.path(OUT_DIR, "crosswalk_variables.csv"), na = "")
write_csv(values,          file.path(OUT_DIR, "crosswalk_values.csv"),    na = "")
write_csv(countries,       file.path(OUT_DIR, "countries.csv"),           na = "")
write_csv(country_aliases, file.path(OUT_DIR, "country_aliases.csv"),     na = "")
write_csv(coverage,        file.path(OUT_DIR, "coverage_by_item.csv"),    na = "")

pres <- variables %>% filter(present)
stopifnot(
  # every value row has a present variable row
  nrow(anti_join(values, pres, by = c("canonical_code", "round_number"))) == 0,
  # a missing code NEVER carries a harmonized value  (the schema CHECK, enforced early)
  nrow(filter(values, is_missing, !is.na(value_harmonized))) == 0,
  nrow(filter(values, !is_missing, is.na(value_harmonized))) == 0,
  # no unverified rows left
  nrow(filter(pres, !verified)) == 0
)
message(sprintf(
  "OK  variables=%d (present %d) | values=%d (missing %d) | countries=%d from %d raw strings",
  nrow(variables), nrow(pres), nrow(values), sum(values$is_missing),
  nrow(countries), nrow(country_aliases)))
not_all <- variables %>% filter(present, !asked_all_countries)
if (nrow(region_changes)) {
  message(sprintf("Region reclassified across rounds for %d countries (most recent used): %s",
                  nrow(region_changes), paste(region_changes$k, collapse = ", ")))
}
if (nrow(not_all)) {
  message("Items not asked in every country:")
  walk2(not_all$canonical_code, not_all$countries_excluded,
        ~ message(sprintf("   %s -> %s", .x, .y)))
}
