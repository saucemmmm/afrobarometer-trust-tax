-- =============================================================================
-- 01_schema.sql  --  normalized target schema (outline Phase 4)
--
-- Purpose : define the `core` schema that the Afrobarometer rounds 6-9 panel is
--           built into. Concept, encoding and response are separated so that
--           every harmonization decision is stored as data rather than baked
--           into a script.
-- Run     : 1st, via  Rscript R/05_build_database.R  (from the repository root).
-- Or directly:  duckdb data/afrobarometer.duckdb -c ".read sql/01_schema.sql"
-- Idempotent: drops and recreates `core` in full.
--
-- Design notes (expanded in README):
--   * `responses` is LONG (one row per respondent x question). This is the
--     correct normalization and it is slower than a wide table for analysis.
--     The cost is accepted because the alternative hard-codes round-specific
--     variable names into the load step, which is the exact problem this
--     project exists to solve. Aggregation happens once, in sql/analysis/.
--   * DEMOGRAPHICS ARE COLUMNS on `respondents`, not rows in `responses`.
--     They are attributes of the person, not survey items of interest, and
--     every analysis query needs them. Their round-specific codes still live
--     in question_map/response_values, so the decode path is identical --
--     only the destination differs.
--   * `country_aliases` exists because country NAMES drift across rounds.
--     See the comment on that table; this is not defensive over-engineering.
-- =============================================================================

DROP SCHEMA IF EXISTS core CASCADE;
CREATE SCHEMA core;
CREATE SCHEMA IF NOT EXISTS staging;   -- populated by 02_load_staging.sql

-- -----------------------------------------------------------------------------
-- rounds
-- `within_weight_variable` is a column, not a constant, because Afrobarometer
-- changed the within-country weight definition at R8: R6/R7 ship `withinwt`,
-- R8/R9 ship `withinwt_ea` (EA-level, "old AB withinwt") and `withinwt_hh`
-- (household-level, "new"). We use the EA version throughout because it is the
-- definition continuous with R6/R7. Recording the source variable here makes
-- that choice inspectable instead of buried in a load script.
-- -----------------------------------------------------------------------------
CREATE TABLE core.rounds (
    round_id                INTEGER      PRIMARY KEY,
    round_number            INTEGER      NOT NULL UNIQUE,
    fieldwork_start          DATE,
    fieldwork_end            DATE,
    n_countries              INTEGER,
    n_respondents            INTEGER,
    within_weight_variable   VARCHAR      NOT NULL,
    combined_weight_variable VARCHAR
);

-- -----------------------------------------------------------------------------
-- countries  --  one row per country, canonical spelling
-- -----------------------------------------------------------------------------
CREATE TABLE core.countries (
    country_id    INTEGER     PRIMARY KEY,
    country_name  VARCHAR     NOT NULL UNIQUE,   -- canonical
    iso3          VARCHAR(3),                    -- optional; unused by any query
    region        VARCHAR                        -- from COUNTRY.BY.REGION (absent in R8)
);

-- -----------------------------------------------------------------------------
-- country_aliases  --  every raw COUNTRY string, mapped to a country_id
--
-- DATA-QUALITY FINDING, not defensive design. Across rounds 6-9 the merged
-- files use 46 distinct country strings for 42 countries:
--     Cote d'Ivoire (R6)            -> Côte d'Ivoire (R7-9)     diacritic
--     Cape Verde    (R6)            -> Cabo Verde    (R7-9)     renaming
--     Swaziland (R6), eSwatini (R7) -> Eswatini      (R8/R9)    2018 RENAME
--
-- The outline's Phase 6 sketch joins on `c.country_name = s.country`. That join
-- silently splits Eswatini into two country_ids and drops it from any balanced
-- panel -- and no string-similarity heuristic recovers Swaziland -> Eswatini,
-- because it is a political rename rather than a spelling variant. Loading
-- through this table makes the mapping explicit and auditable.
-- -----------------------------------------------------------------------------
CREATE TABLE core.country_aliases (
    country_name_raw VARCHAR PRIMARY KEY,
    country_id       INTEGER NOT NULL REFERENCES core.countries(country_id),
    is_alias         BOOLEAN NOT NULL DEFAULT FALSE   -- TRUE where raw <> canonical
);

-- -----------------------------------------------------------------------------
-- country_rounds  --  resolves the many-to-many; coverage is a queryable fact
-- Country coverage changes every round (36/34/34/39). A missing row here is the
-- finding, not an accident -- see sql/analysis/coverage_report.sql.
-- -----------------------------------------------------------------------------
CREATE TABLE core.country_rounds (
    country_id     INTEGER NOT NULL REFERENCES core.countries(country_id),
    round_id       INTEGER NOT NULL REFERENCES core.rounds(round_id),
    n_respondents  INTEGER,
    PRIMARY KEY (country_id, round_id)
);

-- -----------------------------------------------------------------------------
-- respondents
-- respondent_id is round-prefixed ('R9_' || respno). RESPNO is unique WITHIN a
-- round only; without the prefix the primary key collides across rounds.
-- -----------------------------------------------------------------------------
CREATE TABLE core.respondents (
    respondent_id    VARCHAR  PRIMARY KEY,
    respno_raw       VARCHAR  NOT NULL,
    country_id       INTEGER  NOT NULL REFERENCES core.countries(country_id),
    round_id         INTEGER  NOT NULL REFERENCES core.rounds(round_id),
    region_name      VARCHAR,                    -- within-country province/region
    interview_date   DATE,
    within_weight    DOUBLE   NOT NULL,          -- withinwt / withinwt_ea
    combined_weight  DOUBLE,
    -- harmonized demographics (see design note above)
    urban_rural      VARCHAR  CHECK (urban_rural IN ('Urban','Rural')),
    age              INTEGER  CHECK (age IS NULL OR age BETWEEN 15 AND 130),
    gender           VARCHAR  CHECK (gender IN ('Male','Female')),
    education_level  INTEGER  CHECK (education_level IS NULL OR education_level BETWEEN 0 AND 9),
    lived_poverty    DOUBLE   CHECK (lived_poverty IS NULL OR lived_poverty BETWEEN 0 AND 4),
    CHECK (within_weight > 0)
);

-- -----------------------------------------------------------------------------
-- questions  --  the canonical CONCEPT, one row regardless of how many rounds
-- ask it or how many different codes they use. scale_type here is the
-- HARMONIZED scale; the raw per-round scale lives on question_map, because it
-- can differ by round.
-- -----------------------------------------------------------------------------
CREATE TABLE core.questions (
    question_id     INTEGER PRIMARY KEY,
    canonical_code  VARCHAR NOT NULL UNIQUE,   -- 'trust_police'
    concept         VARCHAR NOT NULL,          -- 'institutional_trust'
    role            VARCHAR NOT NULL           -- outcome_component | covariate | ...
                    CHECK (role IN ('outcome_component','covariate','demographic',
                                    'control','weight','extension','lpi_component')),
    scale_type      VARCHAR,                   -- harmonized: 'likert_0_3', ...
    higher_means    VARCHAR                    -- direction, so signs cannot be misread
);

-- -----------------------------------------------------------------------------
-- question_map  --  THE CROSSWALK. One row per concept x round.
--
-- Rows exist for rounds where the item is ABSENT (`present = FALSE`), because a
-- missing row and a "not asked" row are different facts and only one of them is
-- evidence that the codebook was checked.
--
-- question_text is stored PER ROUND because wording drifts. The known cases:
--   corruption_govt_officials  R6/R7 "government officials" -> R8/R9 "civil servants"
--   govt_perf_economy          R7+ adds "the performance of" to the stem
--   trust_tax_authority        R6 "[Tax Department]" -> R8 "tax/revenue office"
--   lp_*                       stem "gone without" moves position at R8
-- -----------------------------------------------------------------------------
CREATE TABLE core.question_map (
    round_id                 INTEGER NOT NULL REFERENCES core.rounds(round_id),
    question_id              INTEGER NOT NULL REFERENCES core.questions(question_id),
    present                  BOOLEAN NOT NULL,
    round_variable           VARCHAR,          -- 'Q52H'; NULL when present = FALSE
    variable_label           VARCHAR,
    question_text            VARCHAR,          -- verbatim, per round
    raw_scale_type           VARCHAR,
    n_substantive_categories INTEGER,
    asked_all_countries      BOOLEAN,          -- DERIVED from data, not transcribed
    countries_excluded       VARCHAR,
    codebook_source          VARCHAR,
    codebook_note            VARCHAR,
    codebook_page            INTEGER,          -- PDF page, not printed page
    verified                 BOOLEAN NOT NULL DEFAULT FALSE,
    notes                    VARCHAR,
    PRIMARY KEY (round_id, question_id),
    CHECK (present = FALSE OR round_variable IS NOT NULL)
);

-- -----------------------------------------------------------------------------
-- response_values  --  value-label decoding, per concept x round x raw code
--
-- The CHECK below is the schema-level enforcement of the project's hardest
-- rule: a missing code must never carry a harmonized value. Afrobarometer's
-- missing conventions are not constant (R6 codes Refused as 98 where R7-R9 use
-- 8; R6 additionally uses 99 = "Not asked in this country"), and -- the trap --
-- on education_level 9 = "Post-graduate" is VALID while 98/99 are missing. Any
-- round-invariant or code-invariant rule silently corrupts a variable.
-- Missingness is a property of the ITEM, not of the code.
-- -----------------------------------------------------------------------------
CREATE TABLE core.response_values (
    question_id        INTEGER NOT NULL REFERENCES core.questions(question_id),
    round_id           INTEGER NOT NULL REFERENCES core.rounds(round_id),
    value_raw          INTEGER NOT NULL,
    value_label        VARCHAR,
    value_harmonized   INTEGER,          -- NULL for every missing code
    is_missing         BOOLEAN NOT NULL,
    harmonization_rule VARCHAR,          -- 'direct' | 'collapsed ...' | 'missing'
    notes              VARCHAR,
    PRIMARY KEY (question_id, round_id, value_raw),
    CHECK (NOT (is_missing AND value_harmonized IS NOT NULL)),
    CHECK (is_missing OR value_harmonized IS NOT NULL)
);

-- -----------------------------------------------------------------------------
-- responses  --  long format, raw codes only. Decoding happens by joining
-- response_values, so the harmonization is never silently pre-applied.
-- Expect roughly 2 million rows for 11 survey items x 201,286 respondents.
-- -----------------------------------------------------------------------------
CREATE TABLE core.responses (
    respondent_id VARCHAR NOT NULL REFERENCES core.respondents(respondent_id),
    question_id   INTEGER NOT NULL REFERENCES core.questions(question_id),
    value_raw     INTEGER,
    PRIMARY KEY (respondent_id, question_id)
);

-- -----------------------------------------------------------------------------
-- Indexes for the aggregation path used by sql/analysis/*.sql
-- -----------------------------------------------------------------------------
CREATE INDEX idx_respondents_country_round ON core.respondents (country_id, round_id);
CREATE INDEX idx_responses_question        ON core.responses   (question_id);
CREATE INDEX idx_response_values_lookup    ON core.response_values (question_id, round_id, value_raw);
