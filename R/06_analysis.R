# R/06_analysis.R  --  analysis (outline Phase 9)
#
# Runs end to end from a fresh clone after R/01-05 and reproduces every number
# in docs/memo.md.  Usage:  Rscript R/06_analysis.R   (from the repository root)
#
# =============================================================================
# THIS ANALYSIS IS DESCRIPTIVE.
# Two-way fixed effects on observational cross-country survey data does not
# identify a causal effect. Trust, perceived corruption and perceived economic
# performance plausibly respond to the same unobserved shocks, and reverse
# causation is live. Nothing below is an estimate of what would happen if
# corruption or performance were changed. See docs/question.md, section 2.
# =============================================================================
#
# Division of labour, per the project design: SQL owns extraction, harmonization
# and aggregation; R owns inference. Every input here is a view in the database.
#
# Three inference layers, reported together rather than picking the friendliest:
#   1. conventional cluster-robust SEs at country level  (the default answer)
#   2. CR2 + Satterthwaite degrees of freedom            (small-cluster correction)
#   3. wild cluster bootstrap-t, null imposed            (belt and braces)
# The panel has 31-42 country clusters. That is few enough that layer 1 is
# optimistic, and the Satterthwaite degrees of freedom below show how optimistic.

suppressPackageStartupMessages({
  library(DBI); library(duckdb); library(dplyr); library(tidyr)
  library(survey); library(fixest); library(clubSandwich); library(readr)
})
source("R/00_utils.R")   # wild_cluster_boot()

DB_PATH <- Sys.getenv("DB_PATH", "data/afrobarometer.duckdb")
OUT_DIR <- Sys.getenv("RESULTS_DIR", "output")
B_BOOT  <- as.integer(Sys.getenv("B_BOOT", "999"))

# Preflight. The alternative is a raw DuckDB catalog error that says a view is
# missing but not why or what to do about it.
REQUIRED_VIEWS <- c("v_micro", "analysis_panel", "analysis_panel_balanced")

preflight <- function(con) {
  if (!dir.exists("R") || !dir.exists("sql"))
    stop("Run this from the REPOSITORY ROOT (the folder containing R/ and sql/), ",
         "not from the folder the file happens to live in. Current wd: ", getwd(),
         call. = FALSE)
  have <- dbGetQuery(con, "
      SELECT table_name FROM information_schema.tables WHERE table_schema = 'core'
      UNION ALL
      SELECT view_name AS table_name FROM duckdb_views() WHERE schema_name = 'core'")$table_name
  missing <- setdiff(REQUIRED_VIEWS, have)
  if (length(missing))
    stop("The database is missing: ", paste(missing, collapse = ", "), ".\n",
         "  These views are created by the analysis SQL, which runs as part of the build.\n",
         "  Fix:  Rscript R/05_build_database.R --fresh\n",
         "  (If you built the database before the analysis queries were added, this is expected.)",
         call. = FALSE)
  invisible(TRUE)
}

main <- function() {
  if (!file.exists(DB_PATH))
    stop("No database at '", DB_PATH, "'. Build it first:\n",
         "  Rscript R/04_convert_sav.R  &&  Rscript R/05_build_database.R --fresh",
         call. = FALSE)
  dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
  con <- dbConnect(duckdb::duckdb(), DB_PATH, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  preflight(con)

  micro    <- dbGetQuery(con, "SELECT * FROM core.v_micro")
  panel    <- dbGetQuery(con, "SELECT * FROM core.analysis_panel")
  panel_b  <- dbGetQuery(con, "SELECT * FROM core.analysis_panel_balanced")
  for (d in c("panel", "panel_b")) {
    x <- get(d); x$country <- factor(x$country_id); x$round <- factor(x$round_number)
    assign(d, x)
  }
  message(sprintf("micro %s rows | panel %d rows, %d countries | balanced %d rows, %d countries",
                  format(nrow(micro), big.mark = ","), nrow(panel), n_distinct(panel$country_id),
                  nrow(panel_b), n_distinct(panel_b$country_id)))

  # ---------------------------------------------------------------------------
  # 0. What listwise deletion will remove, stated BEFORE it happens silently.
  #    Sudan R6 is here because govt_perf_economy was not asked in Sudan that
  #    round -- the coverage gap documented in docs/question.md 6.2 propagating
  #    into the estimation sample.
  # ---------------------------------------------------------------------------
  dropped <- panel %>%
    filter(if_any(c(wmean_trust_index, wmean_corruption_govt, wmean_govt_perf_economy), is.na)) %>%
    select(country_name, round_number, wmean_trust_index,
           wmean_corruption_govt, wmean_govt_perf_economy)
  message("\nCountry-rounds dropped by listwise deletion: ", nrow(dropped))
  if (nrow(dropped)) print(as.data.frame(dropped), row.names = FALSE)
  write_csv(dropped, file.path(OUT_DIR, "dropped_country_rounds.csv"))

  # ---------------------------------------------------------------------------
  # 1. DESCRIPTIVES with survey weights.
  #    ids = ~country_id treats the country as the primary sampling unit, which
  #    is the level clustering is done at throughout. ids = ~1 would treat the
  #    sample as simple random and understate every standard error.
  #    Weights are not optional: Afrobarometer samples are stratified, so an
  #    unweighted mean estimates the wrong quantity.
  # ---------------------------------------------------------------------------
  des <- svydesign(ids = ~country_id, weights = ~within_weight,
                   data = micro[!is.na(micro$trust_enforcement_index), ])

  overall  <- svymean(~trust_enforcement_index, des, na.rm = TRUE)
  by_round <- svyby(~trust_enforcement_index, ~round_id, des, svymean, na.rm = TRUE)
  by_reg   <- svyby(~trust_enforcement_index, ~region + round_id, des, svymean, na.rm = TRUE)

  cat("\n=== Weighted mean trust in enforcement institutions (0-3) ===\n")
  print(overall); cat("\n-- by round --\n"); print(by_round, row.names = FALSE)

  write_csv(as_tibble(by_round), file.path(OUT_DIR, "weighted_means_by_round.csv"))
  write_csv(as_tibble(by_reg),   file.path(OUT_DIR, "weighted_means_by_region_round.csv"))

  # ---------------------------------------------------------------------------
  # 2. COUNTRY-ROUND PANEL, two-way fixed effects.
  #    Country FE absorb time-invariant country characteristics; round FE absorb
  #    shocks common to a wave. The identifying variation is within-country,
  #    across rounds. Cells are equally weighted: each is already a weighted mean
  #    of ~1,200 respondents, and weighting cells by n would let the largest
  #    samples dominate a country-level comparison.
  # ---------------------------------------------------------------------------
  fml <- wmean_trust_index ~ wmean_corruption_govt + wmean_govt_perf_economy
  m_panel <- feols(wmean_trust_index ~ wmean_corruption_govt + wmean_govt_perf_economy |
                     country + round, data = panel,   cluster = ~country)
  m_bal   <- feols(wmean_trust_index ~ wmean_corruption_govt + wmean_govt_perf_economy |
                     country + round, data = panel_b, cluster = ~country)

  cat("\n=== Two-way FE, country-round panel ===\n")
  print(etable(m_panel, m_bal, headers = c("full (unbalanced)", "balanced"),
               fitstat = ~ n + r2 + ar2))

  # --- Cross-check: fixest against lm with explicit dummies -------------------
  # The two must agree to numerical tolerance. This guards against a silently
  # wrong FE specification, which is easy to write and hard to notice.
  lm_check <- lm(update(fml, . ~ . + country + round), data = panel)
  stopifnot(all.equal(unname(coef(m_panel)[c("wmean_corruption_govt","wmean_govt_perf_economy")]),
                      unname(coef(lm_check)[c("wmean_corruption_govt","wmean_govt_perf_economy")]),
                      tolerance = 1e-8))
  message("fixest and lm-with-dummies agree to 1e-8.")

  # ---------------------------------------------------------------------------
  # 3. SMALL-CLUSTER INFERENCE.
  #    With ~42 clusters the conventional cluster-robust p-value is optimistic.
  #    CR2 with Satterthwaite degrees of freedom and the wild cluster bootstrap
  #    are reported alongside it, not instead of it.
  # ---------------------------------------------------------------------------
  keys <- c("wmean_corruption_govt", "wmean_govt_perf_economy")

  # A country observed in ONE round only is a fixed-effect singleton: its country
  # dummy fits that single observation exactly, so it contributes nothing to the
  # within-country slope. fixest removes such rows automatically; lm does not,
  # and silently keeping them makes the two report different N, different cluster
  # counts and different degrees of freedom for an identical estimate. Six
  # countries are affected here -- Algeria, Burundi, Congo-Brazzaville, Egypt,
  # Mauritania, Seychelles -- taking the identifying sample from 142 to 136 rows
  # and 42 clusters to 36. Dropping them here keeps every inference layer
  # describing the SAME estimating sample.
  drop_fe_singletons <- function(dat) {
    dat <- dat[stats::complete.cases(dat[, all.vars(fml)]), ]
    keep <- names(which(table(droplevels(dat$country)) > 1))
    droplevels(dat[as.character(dat$country) %in% keep, ])
  }

  inference <- function(dat, label) {
    dat <- drop_fe_singletons(dat)
    lmx <- lm(update(fml, . ~ . + country + round), data = dat)
    cr1 <- coef_test(lmx, vcov = "CR1S", cluster = dat$country, test = "naive-t")
    cr2 <- coef_test(lmx, vcov = "CR2",  cluster = dat$country, test = "Satterthwaite")
    wcb <- lapply(keys, function(k)
      wild_cluster_boot(update(fml, . ~ . + country + round), dat, dat$country, k, B = B_BOOT))
    tibble(
      sample     = label,
      term       = keys,
      estimate   = cr1$beta[match(keys, cr1$Coef)],
      se_cr1     = cr1$SE[match(keys, cr1$Coef)],
      p_cr1      = cr1$p_t[match(keys, cr1$Coef)],
      se_cr2     = cr2$SE[match(keys, cr2$Coef)],
      df_satt    = cr2$df_Satt[match(keys, cr2$Coef)],
      p_cr2      = cr2$p_Satt[match(keys, cr2$Coef)],
      p_wildboot = vapply(wcb, function(z) z$p_value, numeric(1)),
      n_clusters = vapply(wcb, function(z) z$G, numeric(1)),
      n_obs      = vapply(wcb, function(z) z$n, numeric(1))
    )
  }
  results <- bind_rows(inference(panel,   "full (unbalanced)"),
                       inference(panel_b, "balanced"))
  cat("\n=== Three inference layers, reported together ===\n")
  print(as.data.frame(results), row.names = FALSE, digits = 3)
  write_csv(results, file.path(OUT_DIR, "panel_twoway_fe_inference.csv"))

  # ---------------------------------------------------------------------------
  # 4. INDIVIDUAL LEVEL, same design, survey-weighted.
  #    Aggregation to country-round means throws away within-country variation;
  #    this checks the association is not an artefact of it. Weights are the
  #    within-country survey weights; SEs are clustered at country.
  # ---------------------------------------------------------------------------
  m_micro <- feols(
    trust_enforcement_index ~ corruption_govt + govt_perf_economy +
      age + education_level + lived_poverty + urban_rural + gender |
      country_id + round_id,
    data = micro, weights = ~within_weight, cluster = ~country_id)
  cat("\n=== Individual level, weighted, country+round FE ===\n")
  print(etable(m_micro, fitstat = ~ n + r2))
  message(
    "CAUTION: the stars on the individual-level model are asymptotic and clustered\n",
    "  on the same ~36-42 countries. The large N is respondents, NOT clusters, and\n",
    "  inference is governed by the cluster count. Treat this model as a check that\n",
    "  the panel association is not an artefact of aggregation -- take the reported\n",
    "  p-values from the panel model's CR2 and bootstrap columns instead.")
  write_csv(broom_tidy(m_micro), file.path(OUT_DIR, "micro_twoway_fe.csv"))

  message("\nResults written to ", OUT_DIR, "/")
  message("REMINDER: descriptive association only. No causal language in the memo.")
}

# Minimal tidier so the script does not depend on broom.
broom_tidy <- function(m) {
  s <- summary(m)$coeftable
  tibble::tibble(term = rownames(s), estimate = s[, 1], std_error = s[, 2],
                 statistic = s[, 3], p_value = s[, 4])
}

main()
