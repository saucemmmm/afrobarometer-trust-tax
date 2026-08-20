-- =============================================================================
-- 02_load_staging.sql  --  register one staging table per round (outline Phase 3.3)
--
-- Purpose : load the Parquet files written by R/04_convert_sav.R into a
--           `staging` schema. ALL columns are kept; column selection happens in
--           04_normalize.sql via the crosswalk, so no round-specific variable
--           name is ever hard-coded in a load step.
-- Run     : 2nd, FROM THE REPOSITORY ROOT (the read_parquet paths are relative).
--           Rscript R/05_build_database.R  runs 01-03 in order.
--
-- Tables not views: the staging data is joined repeatedly by 04_normalize.sql,
-- and the .duckdb file is gitignored and rebuilt from raw, so the duplication
-- costs nothing that matters.
--
-- Note on COUNTRY: staging carries both the raw numeric code (COUNTRY) and the
-- decoded name (COUNTRY_LABEL). The numeric code is round-specific -- each round
-- assigns its own code ranges -- so it cannot join across rounds. COUNTRY_LABEL
-- joins through core.country_aliases, which absorbs the spelling drift.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.r6 AS SELECT * FROM read_parquet('data/staging/r6.parquet');
CREATE OR REPLACE TABLE staging.r7 AS SELECT * FROM read_parquet('data/staging/r7.parquet');
CREATE OR REPLACE TABLE staging.r8 AS SELECT * FROM read_parquet('data/staging/r8.parquet');
CREATE OR REPLACE TABLE staging.r9 AS SELECT * FROM read_parquet('data/staging/r9.parquet');

-- -----------------------------------------------------------------------------
-- Reconciliation. Expected counts are the published round totals, recorded in
-- R/04_convert_sav.R. `reconciles` must be true on every row before proceeding.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW staging.load_report AS
WITH loaded AS (
    SELECT 6 AS round_number, COUNT(*) AS n_rows, COUNT(DISTINCT COUNTRY_LABEL) AS n_countries FROM staging.r6
    UNION ALL
    SELECT 7, COUNT(*), COUNT(DISTINCT COUNTRY_LABEL) FROM staging.r7
    UNION ALL
    SELECT 8, COUNT(*), COUNT(DISTINCT COUNTRY_LABEL) FROM staging.r8
    UNION ALL
    SELECT 9, COUNT(*), COUNT(DISTINCT COUNTRY_LABEL) FROM staging.r9
),
expected(round_number, expected_rows) AS (
    VALUES (6, 53935), (7, 45823), (8, 48084), (9, 53444)
)
SELECT l.round_number, l.n_rows, e.expected_rows, l.n_countries,
       l.n_rows = e.expected_rows AS reconciles
FROM loaded l JOIN expected e USING (round_number)
ORDER BY l.round_number;

SELECT * FROM staging.load_report;
