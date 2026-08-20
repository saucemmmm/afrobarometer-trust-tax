-- =============================================================================
-- analysis/panel_country_round.sql
--
-- Question : what is the survey-weighted country-round mean of the outcome and
--            each covariate, restricted to cells with adequate sample size?
-- Techniques: CTEs, four-table join, weighted aggregation, HAVING-style guard.
-- Creates  : core.v_micro        respondent level, for survey::svydesign in R
--            core.analysis_panel country-round level, the handoff to fixest
-- Run first among the analysis files: the other three build on these views.
--
-- WEIGHTS ARE NOT OPTIONAL. Afrobarometer samples are stratified and clustered;
-- an unweighted mean estimates the wrong quantity. Every mean below is
-- SUM(x*w)/SUM(w) over the non-missing subset, with the weight from
-- core.rounds.within_weight_variable (withinwt in R6/R7, withinwt_ea in R8/R9 --
-- the definition continuous across the R7/R8 break).
--
-- DESCRIPTIVE ONLY. These are weighted means and their differences. Nothing
-- here identifies a causal effect.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Respondent level. Decoding happens HERE, by joining response_values -- the
-- raw codes in core.responses are never interpreted anywhere else. Rows where
-- response_values marks the code missing are dropped, which is the only correct
-- treatment: 9 = "Don't know" is not a low score.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW core.v_micro AS
WITH decoded AS (
    SELECT p.respondent_id, q.canonical_code, v.value_harmonized
    FROM core.responses r
    JOIN core.respondents    p USING (respondent_id)
    JOIN core.questions      q USING (question_id)
    JOIN core.response_values v
         ON v.question_id = r.question_id
        AND v.round_id    = p.round_id
        AND v.value_raw   = r.value_raw
    WHERE NOT v.is_missing
),
items AS (
    SELECT respondent_id,
           MAX(value_harmonized) FILTER (WHERE canonical_code = 'trust_police')              AS trust_police,
           MAX(value_harmonized) FILTER (WHERE canonical_code = 'trust_courts')              AS trust_courts,
           MAX(value_harmonized) FILTER (WHERE canonical_code = 'corruption_govt_officials') AS corruption_govt,
           MAX(value_harmonized) FILTER (WHERE canonical_code = 'govt_perf_economy')         AS govt_perf_economy,
           MAX(value_harmonized) FILTER (WHERE canonical_code = 'corruption_tax_officials')  AS corruption_tax,
           MAX(value_harmonized) FILTER (WHERE canonical_code = 'trust_tax_authority')       AS trust_tax_authority
    FROM decoded GROUP BY 1
)
SELECT p.respondent_id, p.country_id, c.country_name, c.region,
       p.round_id, p.within_weight, p.interview_date,
       p.urban_rural, p.age, p.gender, p.education_level, p.lived_poverty,
       i.trust_police, i.trust_courts,
       -- The outcome. Both components required: averaging over whichever
       -- happens to be present would make the index mean different things for
       -- different respondents.
       CASE WHEN i.trust_police IS NOT NULL AND i.trust_courts IS NOT NULL
            THEN (i.trust_police + i.trust_courts) / 2.0 END AS trust_enforcement_index,
       i.corruption_govt, i.govt_perf_economy,
       i.corruption_tax, i.trust_tax_authority          -- coverage-limited extension
FROM core.respondents p
JOIN core.countries   c USING (country_id)
LEFT JOIN items       i USING (respondent_id);

-- -----------------------------------------------------------------------------
-- Country-round panel. The HAVING guard drops cells too thin to carry a mean.
-- Dropped cells are not silently discarded -- core.thin_cells lists them, and
-- the README reports the count.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW core.analysis_panel AS
SELECT m.country_id, m.country_name, m.region, m.round_id AS round_number,
       COUNT(*)                                                    AS n_respondents,
       COUNT(m.trust_enforcement_index)                            AS n_valid_outcome,
       SUM(m.trust_enforcement_index * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.trust_enforcement_index IS NOT NULL) AS wmean_trust_index,
       SUM(m.corruption_govt * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.corruption_govt IS NOT NULL)         AS wmean_corruption_govt,
       SUM(m.govt_perf_economy * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.govt_perf_economy IS NOT NULL)       AS wmean_govt_perf_economy,
       SUM(m.lived_poverty * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.lived_poverty IS NOT NULL)           AS wmean_lived_poverty,
       SUM(CASE WHEN m.urban_rural = 'Urban' THEN 1.0 ELSE 0 END * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.urban_rural IS NOT NULL)             AS wshare_urban,
       SUM(CASE WHEN m.gender = 'Female' THEN 1.0 ELSE 0 END * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.gender IS NOT NULL)                  AS wshare_female,
       SUM(m.age * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.age IS NOT NULL)                     AS wmean_age,
       SUM(m.education_level * m.within_weight)
         / SUM(m.within_weight) FILTER (WHERE m.education_level IS NOT NULL)         AS wmean_education
FROM core.v_micro m
GROUP BY 1,2,3,4
HAVING COUNT(m.trust_enforcement_index) >= 200;   -- thin-cell guard; see below

-- The cells the guard removes. Reported, not hidden: a silent truncation reads
-- as "covered everything" when it did not.
CREATE OR REPLACE VIEW core.thin_cells AS
SELECT country_name, round_id AS round_number,
       COUNT(*) AS n_respondents, COUNT(trust_enforcement_index) AS n_valid_outcome
FROM core.v_micro GROUP BY 1,2
HAVING COUNT(trust_enforcement_index) < 200
ORDER BY n_valid_outcome;
