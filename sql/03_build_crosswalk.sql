-- =============================================================================
-- 03_build_crosswalk.sql  --  load the crosswalk into core (outline Phase 5)
--
-- Purpose : populate countries, country_aliases, rounds, questions,
--           question_map and response_values from the five CSVs produced by
--           R/03_build_crosswalk.R. This is the harmonization core: after this
--           script runs, every decision about what a code MEANS lives in the
--           database as data, and 04_normalize.sql needs no variable names.
-- Run     : 3rd, from the repository root, after 01 and 02.
--             duckdb data/afrobarometer.duckdb < sql/03_build_crosswalk.sql
--
-- The CSVs are inputs, not outputs: regenerate them with R/03, never edit the
-- loaded tables in place.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Countries and their aliases
-- -----------------------------------------------------------------------------
DELETE FROM core.country_aliases;
DELETE FROM core.countries;

INSERT INTO core.countries (country_id, country_name, iso3, region)
SELECT country_id, country_name, NULLIF(iso3, ''), NULLIF(region, '')
FROM read_csv('docs/countries.csv', header = true);

INSERT INTO core.country_aliases (country_name_raw, country_id, is_alias)
SELECT country_name_raw, country_id, is_alias
FROM read_csv('docs/country_aliases.csv', header = true);

-- -----------------------------------------------------------------------------
-- 2. Rounds
--
-- n_countries, n_respondents and the fieldwork window are DERIVED from staging
-- rather than typed in, so they cannot drift from the data they describe.
--
-- within_weight_variable comes from the crosswalk and differs by round: R8/R9
-- split the within-country weight into an EA-level version ("old AB withinwt")
-- and a household-level version ("new"). We use the EA version because it is
-- the definition continuous with R6/R7 -- using the household version would
-- make weighted means non-comparable across the R7/R8 boundary.
-- combined_weight_variable is recorded for completeness; no analysis uses it.
-- -----------------------------------------------------------------------------
DELETE FROM core.rounds;

INSERT INTO core.rounds
WITH observed AS (
    SELECT 6 AS round_number, COUNT(*) AS n, COUNT(DISTINCT COUNTRY_LABEL) AS nc,
           MIN(DATEINTR) AS d0, MAX(DATEINTR) AS d1 FROM staging.r6
    UNION ALL SELECT 7, COUNT(*), COUNT(DISTINCT COUNTRY_LABEL), MIN(DATEINTR), MAX(DATEINTR) FROM staging.r7
    UNION ALL SELECT 8, COUNT(*), COUNT(DISTINCT COUNTRY_LABEL), MIN(DATEINTR), MAX(DATEINTR) FROM staging.r8
    UNION ALL SELECT 9, COUNT(*), COUNT(DISTINCT COUNTRY_LABEL), MIN(DATEINTR), MAX(DATEINTR) FROM staging.r9
),
weights AS (
    SELECT CAST(round_number AS INTEGER) AS round_number, round_variable
    FROM read_csv('docs/crosswalk_variables.csv', header = true)
    WHERE canonical_code = 'within_weight' AND present
),
combined(round_number, combined_variable) AS (
    VALUES (6, 'Combinwt'), (7, 'Combinwt'),
           (8, 'Combinwt_old_ea'), (9, 'Combinwt_old_ea')
)
SELECT o.round_number AS round_id,          -- round_id = round_number, deliberately
       o.round_number,
       CAST(o.d0 AS DATE), CAST(o.d1 AS DATE),
       o.nc, o.n,
       w.round_variable, c.combined_variable
FROM observed o
JOIN weights  w USING (round_number)
JOIN combined c USING (round_number)
ORDER BY o.round_number;

-- -----------------------------------------------------------------------------
-- 3. questions  --  one row per CONCEPT, regardless of how many rounds ask it
--
-- scale_type here is the HARMONIZED scale. The raw per-round scale lives on
-- question_map, because it can differ by round.
-- question_id is assigned alphabetically by canonical_code: the value is
-- arbitrary, so a deterministic rule beats file order, which is not guaranteed.
-- -----------------------------------------------------------------------------
DELETE FROM core.response_values;
DELETE FROM core.question_map;
DELETE FROM core.questions;

CREATE OR REPLACE TEMP TABLE cw_vars AS
SELECT canonical_code, concept, role,
       CAST(round_number AS INTEGER)             AS round_number,
       present,
       NULLIF(round_variable, '')                AS round_variable,
       NULLIF(variable_label, '')                AS variable_label,
       NULLIF(question_text, '')                 AS question_text,
       NULLIF(codebook_source, '')               AS codebook_source,
       NULLIF(codebook_note, '')                 AS codebook_note,
       CAST(codebook_page AS INTEGER)            AS codebook_page,
       NULLIF(raw_scale_type, '')                AS raw_scale_type,
       CAST(n_substantive_categories AS INTEGER) AS n_substantive_categories,
       higher_means, asked_all_countries,
       NULLIF(countries_excluded, '')            AS countries_excluded,
       verified,
       NULLIF(notes, '')                         AS notes
FROM read_csv('docs/crosswalk_variables.csv', header = true, all_varchar = true);

INSERT INTO core.questions (question_id, canonical_code, concept, role, scale_type, higher_means)
SELECT ROW_NUMBER() OVER (ORDER BY canonical_code) AS question_id,
       canonical_code, ANY_VALUE(concept), ANY_VALUE(role),
       ANY_VALUE(raw_scale_type), ANY_VALUE(higher_means)
FROM cw_vars
GROUP BY canonical_code;

-- -----------------------------------------------------------------------------
-- 4. question_map  --  THE CROSSWALK
--
-- Rows are inserted for rounds where the item is ABSENT (present = FALSE).
-- A missing row and a "not asked" row are different facts, and only one of them
-- is evidence that the codebook was checked.
-- -----------------------------------------------------------------------------
INSERT INTO core.question_map
SELECT r.round_id, q.question_id, v.present, v.round_variable, v.variable_label,
       v.question_text, v.raw_scale_type, v.n_substantive_categories,
       v.asked_all_countries, v.countries_excluded, v.codebook_source,
       v.codebook_note, v.codebook_page, v.verified, v.notes
FROM cw_vars v
JOIN core.questions q USING (canonical_code)
JOIN core.rounds    r ON r.round_number = v.round_number;

-- -----------------------------------------------------------------------------
-- 5. response_values  --  the decoding table
--
-- Every missing code lands here with value_harmonized = NULL. The CHECK
-- constraints on the table (see 01_schema.sql) make that structural: a missing
-- code cannot carry a value, and a substantive code cannot lack one. If this
-- INSERT fails on a constraint, the crosswalk is wrong -- fix R/03, not the SQL.
-- -----------------------------------------------------------------------------
INSERT INTO core.response_values
SELECT q.question_id, r.round_id,
       CAST(v.value_raw AS INTEGER),
       NULLIF(v.value_label, ''),
       CAST(NULLIF(v.value_harmonized, '') AS INTEGER),
       CAST(v.is_missing AS BOOLEAN),
       NULLIF(v.harmonization_rule, ''),
       NULLIF(v.notes, '')
FROM read_csv('docs/crosswalk_values.csv', header = true, all_varchar = true) v
JOIN core.questions q USING (canonical_code)
JOIN core.rounds    r ON r.round_number = CAST(v.round_number AS INTEGER);

-- -----------------------------------------------------------------------------
-- 6. Verification -- inspect this output, do not assume the loads worked
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW core.crosswalk_report AS
SELECT 'countries'        AS tbl, COUNT(*) AS n FROM core.countries
UNION ALL SELECT 'country_aliases',  COUNT(*) FROM core.country_aliases
UNION ALL SELECT 'aliases (raw <> canonical)', COUNT(*) FROM core.country_aliases WHERE is_alias
UNION ALL SELECT 'rounds',           COUNT(*) FROM core.rounds
UNION ALL SELECT 'questions',        COUNT(*) FROM core.questions
UNION ALL SELECT 'question_map',     COUNT(*) FROM core.question_map
UNION ALL SELECT 'question_map (present)',  COUNT(*) FROM core.question_map WHERE present
UNION ALL SELECT 'question_map (not asked)',COUNT(*) FROM core.question_map WHERE NOT present
UNION ALL SELECT 'response_values',  COUNT(*) FROM core.response_values
UNION ALL SELECT 'response_values (missing)', COUNT(*) FROM core.response_values WHERE is_missing;

SELECT * FROM core.crosswalk_report;

-- The crosswalk as a human-readable grid: concept x round, showing the drift
-- this whole table exists to record.
CREATE OR REPLACE VIEW core.crosswalk_grid AS
SELECT q.canonical_code, q.role,
       MAX(CASE WHEN m.round_id = 6 THEN COALESCE(m.round_variable, '--') END) AS r6,
       MAX(CASE WHEN m.round_id = 7 THEN COALESCE(m.round_variable, '--') END) AS r7,
       MAX(CASE WHEN m.round_id = 8 THEN COALESCE(m.round_variable, '--') END) AS r8,
       MAX(CASE WHEN m.round_id = 9 THEN COALESCE(m.round_variable, '--') END) AS r9
FROM core.questions q JOIN core.question_map m USING (question_id)
GROUP BY q.canonical_code, q.role
ORDER BY q.role, q.canonical_code;

SELECT * FROM core.crosswalk_grid;
