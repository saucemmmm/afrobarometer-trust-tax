-- =============================================================================
-- 04_normalize.sql  --  staging -> normalized core tables (outline Phase 6)
--
-- Purpose : populate country_rounds, respondents and responses from staging,
--           driven ENTIRELY by core.question_map. No round-specific variable
--           name appears anywhere below.
-- Run     : 4th.  Rscript R/05_build_database.R  runs 01-04 in order.
--
-- HOW THE UNPIVOT WORKS, and why it is not a hard-coded column list.
--   Each staging row is serialised with to_json(), giving an object keyed by
--   column name; question_map.round_variable then pulls the field out by name.
--   The variable names live in DATA, not in this script. Add a concept to the
--   crosswalk, re-run, and this file does not change.
--
-- THREE DATA-QUALITY FINDINGS ARE HANDLED HERE.
--
--   (a) RESPNO collides ACROSS rounds, as the outline warns. 201,286 rows carry
--       only 66,429 distinct RESPNO values -- 134,857 collisions; BEN0001
--       exists in all four rounds. Hence the 'R<round>_' prefix.
--
--   (b) RESPNO ALSO collides WITHIN a round, which the outline says cannot
--       happen. R8 has 24 duplicated RESPNO values, all in Sudan, 48 rows
--       (R6/R7/R9 are clean). They are NOT duplicate records: SUD1777 appears
--       twice with different regions, interview dates, ages, genders and
--       weights -- two real respondents issued the same questionnaire number.
--       Dropping them would discard real interviews, so they are disambiguated
--       with a '#n' suffix ordered deterministically by (DATEINTR, REGION_LABEL)
--       so a rebuild reproduces the same ids. core.respno_collisions lists them.
--
--   (c) Because of (b), (round, RESPNO) is NOT a usable join key -- joining on
--       it fans the 48 Sudan rows out into duplicate responses. The key used
--       throughout is (round, RESPNO, REGION_LABEL, DATEINTR), which is unique
--       across all 201,286 rows (verified in core.normalize_report).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Respondent identity. respondent_id is minted ONCE, here, and every other
--    table keys off it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE respondent_base AS
WITH u AS (
    SELECT 6 AS round_number, RESPNO AS respno, COUNTRY_LABEL, REGION_LABEL, DATEINTR FROM staging.r6
    UNION ALL SELECT 7, RESPNO, COUNTRY_LABEL, REGION_LABEL, DATEINTR FROM staging.r7
    UNION ALL SELECT 8, RESPNO, COUNTRY_LABEL, REGION_LABEL, DATEINTR FROM staging.r8
    UNION ALL SELECT 9, RESPNO, COUNTRY_LABEL, REGION_LABEL, DATEINTR FROM staging.r9
),
seq AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY round_number, respno
                                 ORDER BY DATEINTR, REGION_LABEL) AS dup_seq
    FROM u
)
SELECT 'R' || round_number || '_' || respno
       || CASE WHEN dup_seq > 1 THEN '#' || dup_seq ELSE '' END AS respondent_id,
       round_number, respno, COUNTRY_LABEL, REGION_LABEL, DATEINTR, dup_seq
FROM seq;

-- Surfaced rather than silently absorbed -- finding (b).
CREATE OR REPLACE VIEW core.respno_collisions AS
SELECT respondent_id, round_number, respno, COUNTRY_LABEL, REGION_LABEL, DATEINTR, dup_seq
FROM respondent_base
WHERE (round_number, respno) IN (
    SELECT round_number, respno FROM respondent_base GROUP BY 1, 2 HAVING COUNT(*) > 1)
ORDER BY round_number, respno, dup_seq;

-- -----------------------------------------------------------------------------
-- 2. Crosswalk-driven extraction, already carrying respondent_id.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE extracted AS
WITH mapped AS (
    SELECT m.round_id, q.question_id, q.canonical_code, q.role, m.round_variable
    FROM core.question_map m JOIN core.questions q USING (question_id)
    WHERE m.present
),
raw_json AS (
    SELECT 6 AS round_number, RESPNO AS respno, REGION_LABEL, DATEINTR, to_json(s) AS j FROM staging.r6 s
    UNION ALL SELECT 7, RESPNO, REGION_LABEL, DATEINTR, to_json(s) FROM staging.r7 s
    UNION ALL SELECT 8, RESPNO, REGION_LABEL, DATEINTR, to_json(s) FROM staging.r8 s
    UNION ALL SELECT 9, RESPNO, REGION_LABEL, DATEINTR, to_json(s) FROM staging.r9 s
)
SELECT b.respondent_id, r.round_number, m.question_id, m.canonical_code, m.role,
       TRY_CAST(json_extract_string(r.j, '$."' || m.round_variable || '"') AS DOUBLE) AS value_num
FROM raw_json r
JOIN respondent_base b
  ON  b.round_number = r.round_number
  AND b.respno       = r.respno
  AND b.REGION_LABEL IS NOT DISTINCT FROM r.REGION_LABEL      -- finding (c)
  AND b.DATEINTR     IS NOT DISTINCT FROM r.DATEINTR
JOIN mapped m ON m.round_id = r.round_number;

-- response_values decides what is missing. Concepts with no response_values
-- rows (continuous lived_poverty, within_weight) are valid when non-null.
CREATE OR REPLACE VIEW decoded AS
SELECT e.*, rv.value_harmonized,
       COALESCE(rv.is_missing, e.value_num IS NULL) AS is_missing
FROM extracted e
LEFT JOIN core.response_values rv
       ON rv.question_id = e.question_id
      AND rv.round_id    = e.round_number
      AND rv.value_raw   = TRY_CAST(e.value_num AS INTEGER);

-- -----------------------------------------------------------------------------
-- 3. country_rounds  --  coverage as a first-class fact.
--    The join runs through country_aliases, never on the raw name: R6 spells it
--    "Cote d'Ivoire" / "Cape Verde" / "Swaziland" where later rounds use the
--    accented form / "Cabo Verde" / "Eswatini". Joining raw strings would split
--    those countries in two and drop them from any balanced panel.
-- -----------------------------------------------------------------------------
DELETE FROM core.responses;
DELETE FROM core.respondents;
DELETE FROM core.country_rounds;

INSERT INTO core.country_rounds (country_id, round_id, n_respondents)
SELECT a.country_id, b.round_number, COUNT(*)
FROM respondent_base b
JOIN core.country_aliases a ON a.country_name_raw = b.COUNTRY_LABEL
GROUP BY 1, 2;

-- -----------------------------------------------------------------------------
-- 4. respondents
--
--    lived_poverty comes from the shipped LivedPoverty in R7-R9 and is
--    CONSTRUCTED for R6, which ships none. The rule was verified empirically,
--    not assumed: the mean of the five 0-4 components, computed only where ALL
--    FIVE are non-missing. core.lpi_regression_test re-derives it in R7-R9 and
--    checks it reproduces the shipped variable exactly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE lp_constructed AS
SELECT respondent_id,
       CASE WHEN COUNT(*) FILTER (WHERE NOT is_missing) = 5
            THEN AVG(value_harmonized) FILTER (WHERE NOT is_missing) END AS lpi
FROM decoded WHERE role = 'lpi_component'
GROUP BY 1;

CREATE OR REPLACE TEMP TABLE resp_wide AS
SELECT respondent_id,
       MAX(CASE WHEN canonical_code = 'within_weight' THEN value_num END) AS within_weight,
       MAX(CASE WHEN canonical_code = 'age' AND NOT is_missing
                THEN CAST(value_num AS INTEGER) END)                      AS age,
       MAX(CASE WHEN canonical_code = 'education_level' AND NOT is_missing
                THEN value_harmonized END)                                AS education_level,
       MAX(CASE WHEN canonical_code = 'urban_rural' AND NOT is_missing
                THEN CASE value_harmonized WHEN 1 THEN 'Urban' ELSE 'Rural' END END)  AS urban_rural,
       MAX(CASE WHEN canonical_code = 'gender' AND NOT is_missing
                THEN CASE value_harmonized WHEN 1 THEN 'Male' ELSE 'Female' END END)  AS gender,
       MAX(CASE WHEN canonical_code = 'lived_poverty' AND NOT is_missing
                THEN value_num END)                                       AS lived_poverty_shipped
FROM decoded GROUP BY 1;

INSERT INTO core.respondents
SELECT b.respondent_id, b.respno, a.country_id, b.round_number,
       b.REGION_LABEL, b.DATEINTR,
       w.within_weight, NULL AS combined_weight,
       w.urban_rural, w.age, w.gender, w.education_level,
       COALESCE(w.lived_poverty_shipped, lp.lpi) AS lived_poverty
FROM respondent_base b
JOIN core.country_aliases a ON a.country_name_raw = b.COUNTRY_LABEL
JOIN resp_wide w USING (respondent_id)
LEFT JOIN lp_constructed lp USING (respondent_id)
WHERE w.within_weight IS NOT NULL AND w.within_weight > 0;   -- schema requires it

-- -----------------------------------------------------------------------------
-- 5. responses  --  long, RAW codes only. Decoding happens at query time by
--    joining response_values, so no harmonization is silently pre-applied.
--    Demographics, the weight and the derived index are respondent attributes
--    and live on core.respondents; the lp_* components stay here as the
--    auditable source for the constructed index.
-- -----------------------------------------------------------------------------
INSERT INTO core.responses (respondent_id, question_id, value_raw)
SELECT d.respondent_id, d.question_id, TRY_CAST(d.value_num AS INTEGER)
FROM decoded d
JOIN core.respondents p USING (respondent_id)
WHERE d.role IN ('outcome_component', 'covariate', 'extension', 'lpi_component')
  AND d.value_num IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 6. Validation -- read this output, do not assume the inserts were correct
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW core.normalize_report AS
SELECT 'country_rounds rows'                       AS check_name, COUNT(*)::VARCHAR AS value FROM core.country_rounds
UNION ALL SELECT 'respondents',                          COUNT(*)::VARCHAR FROM core.respondents
UNION ALL SELECT 'responses',                            COUNT(*)::VARCHAR FROM core.responses
UNION ALL SELECT 'staging rows (should equal respondents)',
       (SELECT SUM(n_respondents)::VARCHAR FROM core.rounds)
UNION ALL SELECT 'distinct RESPNO ignoring round (illustrates the collision)',
       (SELECT COUNT(DISTINCT respno_raw)::VARCHAR FROM core.respondents)
UNION ALL SELECT 'within-round RESPNO collisions disambiguated',
       (SELECT COUNT(*)::VARCHAR FROM core.respno_collisions)
UNION ALL SELECT 'respondents with NULL/non-positive weight (must be 0)',
       (SELECT COUNT(*)::VARCHAR FROM core.respondents WHERE within_weight IS NULL OR within_weight <= 0)
UNION ALL SELECT 'orphaned responses (must be 0)',
       (SELECT COUNT(*)::VARCHAR FROM core.responses r
         LEFT JOIN core.respondents p USING (respondent_id) WHERE p.respondent_id IS NULL)
UNION ALL SELECT 'response codes absent from response_values (must be 0)',
       (SELECT COUNT(*)::VARCHAR FROM (
           SELECT DISTINCT r.question_id, p.round_id, r.value_raw
           FROM core.responses r JOIN core.respondents p USING (respondent_id)
           EXCEPT SELECT question_id, round_id, value_raw FROM core.response_values))
UNION ALL SELECT 'country_rounds reconcile to respondents (must be 0)',
       (SELECT COUNT(*)::VARCHAR FROM (
           SELECT cr.country_id, cr.round_id FROM core.country_rounds cr
           LEFT JOIN core.respondents p
                  ON p.country_id = cr.country_id AND p.round_id = cr.round_id
           GROUP BY 1, 2, cr.n_respondents HAVING cr.n_respondents <> COUNT(p.respondent_id)))
-- Informational, NOT a failure: LivedPoverty is listwise -- NULL wherever any
-- of the five components is missing. 1,356 such respondents across R7-R9 is
-- the expected figure and matches the shipped variable exactly.
UNION ALL SELECT 'lived_poverty NULL, R7-R9 (expected: listwise, ~1,356)',
       (SELECT COUNT(*)::VARCHAR FROM core.respondents WHERE round_id > 6 AND lived_poverty IS NULL)
UNION ALL SELECT 'lived_poverty NULL, R6 (constructed the same way)',
       (SELECT COUNT(*)::VARCHAR FROM core.respondents WHERE round_id = 6 AND lived_poverty IS NULL);

SELECT * FROM core.normalize_report;

-- Regression test for the constructed index: re-derive LivedPoverty from its
-- components in R7-R9, where the shipped variable exists, and confirm the rule
-- used to construct R6 reproduces it. A non-zero mismatch means the R6 index
-- rests on a rule the data does not support.
CREATE OR REPLACE VIEW core.lpi_regression_test AS
SELECT p.round_id,
       COUNT(*)                                                                  AS n,
       COUNT(*) FILTER (WHERE ABS(w.lived_poverty_shipped - lp.lpi) > 1e-9)      AS mismatches,
       COUNT(*) FILTER (WHERE w.lived_poverty_shipped IS NULL AND lp.lpi IS NOT NULL) AS shipped_null_rebuilt_not,
       COUNT(*) FILTER (WHERE w.lived_poverty_shipped IS NOT NULL AND lp.lpi IS NULL) AS rebuilt_null_shipped_not
FROM core.respondents p
JOIN resp_wide      w  USING (respondent_id)
LEFT JOIN lp_constructed lp USING (respondent_id)
WHERE p.round_id > 6
GROUP BY 1 ORDER BY 1;

SELECT * FROM core.lpi_regression_test;
