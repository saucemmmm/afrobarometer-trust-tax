-- =============================================================================
-- 05_validate.sql  --  data-quality checks (outline Phase 7)
--
-- Purpose : every check below is written so that FAILURES ARE ROWS. A healthy
--           database returns zero rows from core.validation_failures. The
--           summary view lists every check that ran, so a check that silently
--           stopped running is visible as a missing row rather than as silence.
-- Run     : 5th.  Rscript R/05_build_database.R  runs 01-05 in order.
--
-- This is what separates a database from a data dump, and it is the routine
-- work of a research data analyst: reconcile the counts, prove the joins are
-- the cardinality you claimed, and report the missingness rather than
-- discovering it in a regression.
-- =============================================================================

CREATE OR REPLACE VIEW core.validation_checks AS
WITH
-- 1. Referential integrity ----------------------------------------------------
c1 AS (SELECT 'orphaned responses (no matching respondent)' AS check_name, 'error' AS severity,
              COUNT(*) AS n_failing
       FROM core.responses r LEFT JOIN core.respondents p USING (respondent_id)
       WHERE p.respondent_id IS NULL),
c2 AS (SELECT 'respondents pointing at a country not in core.countries', 'error', COUNT(*)
       FROM core.respondents p LEFT JOIN core.countries c USING (country_id)
       WHERE c.country_id IS NULL),
-- 2. Counts reconcile ---------------------------------------------------------
c3 AS (SELECT 'country_rounds.n_respondents <> actual respondent count', 'error', COUNT(*)
       FROM (SELECT cr.country_id, cr.round_id, cr.n_respondents, COUNT(p.respondent_id) AS actual
             FROM core.country_rounds cr
             LEFT JOIN core.respondents p
                    ON p.country_id = cr.country_id AND p.round_id = cr.round_id
             GROUP BY 1,2,3 HAVING cr.n_respondents <> COUNT(p.respondent_id))),
c4 AS (SELECT 'rounds.n_respondents <> actual respondent count', 'error', COUNT(*)
       FROM (SELECT r.round_id, r.n_respondents, COUNT(p.respondent_id) AS actual
             FROM core.rounds r LEFT JOIN core.respondents p USING (round_id)
             GROUP BY 1,2 HAVING r.n_respondents <> COUNT(p.respondent_id))),
-- 3. Every observed code is decodable -----------------------------------------
c5 AS (SELECT 'response codes absent from response_values', 'error', COUNT(*)
       FROM (SELECT DISTINCT r.question_id, p.round_id, r.value_raw
             FROM core.responses r JOIN core.respondents p USING (respondent_id)
             EXCEPT
             SELECT question_id, round_id, value_raw FROM core.response_values)),
-- 4. Weights ------------------------------------------------------------------
c6 AS (SELECT 'weights null or non-positive', 'error', COUNT(*)
       FROM core.respondents WHERE within_weight IS NULL OR within_weight <= 0),
-- 5. The harmonization invariant ----------------------------------------------
--    Enforced by CHECK constraints in 01_schema.sql; re-asserted here because a
--    constraint that is never tested is a constraint you are trusting blindly.
c7 AS (SELECT 'missing code carrying a harmonized value', 'error', COUNT(*)
       FROM core.response_values WHERE is_missing AND value_harmonized IS NOT NULL),
c8 AS (SELECT 'substantive code with no harmonized value', 'error', COUNT(*)
       FROM core.response_values WHERE NOT is_missing AND value_harmonized IS NULL),
-- 6. Crosswalk coherence ------------------------------------------------------
c9 AS (SELECT 'question_map present but no round_variable', 'error', COUNT(*)
       FROM core.question_map WHERE present AND round_variable IS NULL),
c10 AS (SELECT 'coded item present in a round with no response_values rows', 'error', COUNT(*)
        FROM (SELECT m.round_id, m.question_id FROM core.question_map m
              JOIN core.questions q USING (question_id)
              -- continuous and free-numeric items carry no value labels, so they
              -- correctly have no response_values rows. Match on the FAMILY of the
              -- scale, not an exact list: 'continuous_0_4' belongs here too, and an
              -- exact-match list quietly reported it as a failure.
              WHERE m.present
                AND q.scale_type NOT LIKE 'continuous%'
                AND q.scale_type <> 'numeric'
              EXCEPT SELECT round_id, question_id FROM core.response_values)),
c11 AS (SELECT 'responses recorded for a question not mapped to that round', 'error', COUNT(*)
        FROM core.responses r JOIN core.respondents p USING (respondent_id)
        LEFT JOIN core.question_map m
               ON m.question_id = r.question_id AND m.round_id = p.round_id AND m.present
        WHERE m.question_id IS NULL),
-- 7. Key integrity ------------------------------------------------------------
c12 AS (SELECT 'duplicate respondent_id', 'error', COUNT(*)
        FROM (SELECT respondent_id FROM core.respondents
              GROUP BY 1 HAVING COUNT(*) > 1)),
c13 AS (SELECT 'duplicate (respondent, question) in responses', 'error', COUNT(*)
        FROM (SELECT respondent_id, question_id FROM core.responses
              GROUP BY 1,2 HAVING COUNT(*) > 1)),
-- 8. Value ranges on the harmonized demographics ------------------------------
c14 AS (SELECT 'age outside 15-130', 'error', COUNT(*)
        FROM core.respondents WHERE age IS NOT NULL AND (age < 15 OR age > 130)),
c15 AS (SELECT 'education_level outside 0-9', 'error', COUNT(*)
        FROM core.respondents WHERE education_level IS NOT NULL
          AND (education_level < 0 OR education_level > 9)),
c16 AS (SELECT 'lived_poverty outside 0-4', 'error', COUNT(*)
        FROM core.respondents WHERE lived_poverty IS NOT NULL
          AND (lived_poverty < 0 OR lived_poverty > 4)),
-- 9. Design requirements ------------------------------------------------------
--    The outcome needs BOTH components in every round; if one drops, the index
--    silently changes meaning rather than failing.
c17 AS (SELECT 'outcome component missing from a round', 'error', COUNT(*)
        FROM (SELECT r.round_id, q.canonical_code
              FROM core.rounds r CROSS JOIN core.questions q
              WHERE q.role = 'outcome_component'
              EXCEPT
              SELECT m.round_id, q.canonical_code FROM core.question_map m
              JOIN core.questions q USING (question_id)
              WHERE m.present AND q.role = 'outcome_component')),
c18 AS (SELECT 'covariate of interest missing from a round', 'error', COUNT(*)
        FROM (SELECT r.round_id, q.canonical_code
              FROM core.rounds r CROSS JOIN core.questions q WHERE q.role = 'covariate'
              EXCEPT
              SELECT m.round_id, q.canonical_code FROM core.question_map m
              JOIN core.questions q USING (question_id)
              WHERE m.present AND q.role = 'covariate')),
-- 10. Warnings: real, expected, and reported rather than hidden ---------------
c19 AS (SELECT 'WARN within-round RESPNO collisions (expected 48: R8 Sudan)', 'warn', COUNT(*)
        FROM (SELECT round_id, respno_raw FROM core.respondents
              GROUP BY 1,2 HAVING COUNT(*) > 1) t
        JOIN core.respondents p ON p.round_id = t.round_id AND p.respno_raw = t.respno_raw),
c20 AS (SELECT 'WARN country-rounds with <200 valid outcome responses', 'warn', COUNT(*)
        FROM (SELECT p.country_id, p.round_id
              FROM core.responses r
              JOIN core.respondents p USING (respondent_id)
              JOIN core.questions q USING (question_id)
              JOIN core.response_values v
                   ON v.question_id = r.question_id AND v.round_id = p.round_id
                  AND v.value_raw = r.value_raw
              WHERE q.role = 'outcome_component' AND NOT v.is_missing
              GROUP BY 1,2 HAVING COUNT(*) < 400))     -- 400 = 200 respondents x 2 items
SELECT * FROM c1 UNION ALL SELECT * FROM c2  UNION ALL SELECT * FROM c3
UNION ALL SELECT * FROM c4  UNION ALL SELECT * FROM c5  UNION ALL SELECT * FROM c6
UNION ALL SELECT * FROM c7  UNION ALL SELECT * FROM c8  UNION ALL SELECT * FROM c9
UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18
UNION ALL SELECT * FROM c19 UNION ALL SELECT * FROM c20;

-- Failures only. ZERO ROWS when the database is healthy.
CREATE OR REPLACE VIEW core.validation_failures AS
SELECT * FROM core.validation_checks WHERE severity = 'error' AND n_failing > 0;

-- -----------------------------------------------------------------------------
-- Missingness report -- feeds docs/coverage.md
-- Item non-response by concept x round, computed from response_values rather
-- than assumed. `pct_missing` counts respondents who were asked the item and
-- gave a Refused / Don't know / Missing answer.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW core.missingness_report AS
SELECT q.canonical_code, q.role, p.round_id,
       COUNT(*)                                             AS n_answered_rows,
       COUNT(*) FILTER (WHERE v.is_missing)                 AS n_missing,
       ROUND(100.0 * COUNT(*) FILTER (WHERE v.is_missing) / COUNT(*), 2) AS pct_missing
FROM core.responses r
JOIN core.respondents p USING (respondent_id)
JOIN core.questions   q USING (question_id)
JOIN core.response_values v
     ON v.question_id = r.question_id AND v.round_id = p.round_id
    AND v.value_raw   = r.value_raw
GROUP BY 1,2,3 ORDER BY q.role, q.canonical_code, p.round_id;

SELECT * FROM core.validation_checks ORDER BY severity DESC, check_name;
SELECT COUNT(*) AS validation_failures FROM core.validation_failures;
