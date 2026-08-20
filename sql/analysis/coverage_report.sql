-- =============================================================================
-- analysis/coverage_report.sql
--
-- Question : which countries were surveyed in which rounds, which items were
--            asked, and which countries support a balanced cross-round
--            comparison?
-- Technique: CROSS JOIN to build the complete country x round grid, then
--            LEFT JOIN the observed data. THE NULLS ARE THE FINDING.
-- Depends  : core.analysis_panel (for the balanced-panel view)
--
-- This is the query to reach for when asked about LEFT JOIN vs INNER JOIN. An
-- INNER JOIN here answers "what did we observe"; the LEFT JOIN against the full
-- grid answers "what is missing", which is the question that determines whether
-- a cross-round comparison is balanced. Coverage runs 36/34/34/39 countries
-- across rounds 6-9, so the panel is unbalanced by construction, and the
-- composition changes underneath any raw cross-round average.
-- =============================================================================

-- 1. Country x round grid. Every cell exists; status says whether it was filled.
CREATE OR REPLACE VIEW core.coverage_grid AS
SELECT c.country_id, c.country_name, c.region, r.round_number,
       CASE WHEN cr.country_id IS NULL THEN 'not surveyed' ELSE 'surveyed' END AS status,
       cr.n_respondents
FROM core.countries c
CROSS JOIN core.rounds r
LEFT JOIN core.country_rounds cr
       ON cr.country_id = c.country_id AND cr.round_id = r.round_id
ORDER BY c.country_name, r.round_number;

-- 2. One row per country: which rounds it appears in, and whether it is usable
--    for a balanced comparison.
CREATE OR REPLACE VIEW core.country_coverage AS
SELECT country_name, region,
       COUNT(*) FILTER (WHERE status = 'surveyed')                       AS rounds_surveyed,
       STRING_AGG(CASE WHEN status = 'surveyed' THEN round_number::VARCHAR END,
                  '/' ORDER BY round_number)                             AS rounds,
       COUNT(*) FILTER (WHERE status = 'surveyed') = 4                    AS in_balanced_panel,
       SUM(n_respondents)                                                 AS total_respondents
FROM core.coverage_grid
GROUP BY 1,2 ORDER BY rounds_surveyed DESC, country_name;

-- 3. The balanced panel: countries present in ALL four rounds. Every result in
--    the memo is reported on this alongside the full unbalanced panel, so that
--    a change in the composition of countries cannot be mistaken for a change
--    in the outcome.
CREATE OR REPLACE VIEW core.analysis_panel_balanced AS
SELECT p.* FROM core.analysis_panel p
WHERE p.country_id IN (
    SELECT country_id FROM core.country_rounds
    GROUP BY country_id HAVING COUNT(DISTINCT round_id) = 4);

-- 4. Item coverage: which concepts were asked in which rounds, and where an
--    item was asked but not in every country. Absence is recorded as a row
--    (present = FALSE), never as a missing row -- a missing row and a "not
--    asked" row are different facts.
CREATE OR REPLACE VIEW core.item_coverage AS
SELECT q.canonical_code, q.role,
       COUNT(*) FILTER (WHERE m.present)                                AS rounds_asked,
       STRING_AGG(CASE WHEN m.present THEN m.round_id::VARCHAR END,
                  '/' ORDER BY m.round_id)                              AS rounds,
       STRING_AGG(CASE WHEN m.present AND NOT COALESCE(m.asked_all_countries, TRUE)
                       THEN 'R' || m.round_id || ': ' || m.countries_excluded END,
                  '; ')                                                 AS country_exclusions
FROM core.questions q JOIN core.question_map m USING (question_id)
GROUP BY 1,2 ORDER BY q.role, q.canonical_code;

-- 5. Summary for docs/coverage.md
CREATE OR REPLACE VIEW core.coverage_summary AS
SELECT 'countries ever surveyed'  AS metric, COUNT(*)::VARCHAR AS value FROM core.countries
UNION ALL SELECT 'country-rounds observed',   COUNT(*)::VARCHAR FROM core.country_rounds
UNION ALL SELECT 'country-rounds possible (42 x 4)',
       (SELECT COUNT(*)::VARCHAR FROM core.coverage_grid)
UNION ALL SELECT 'cells never surveyed (the NULLs)',
       (SELECT COUNT(*)::VARCHAR FROM core.coverage_grid WHERE status = 'not surveyed')
UNION ALL SELECT 'countries in all 4 rounds (balanced panel)',
       (SELECT COUNT(*)::VARCHAR FROM core.country_coverage WHERE in_balanced_panel)
UNION ALL SELECT 'panel rows, unbalanced',  (SELECT COUNT(*)::VARCHAR FROM core.analysis_panel)
UNION ALL SELECT 'panel rows, balanced',    (SELECT COUNT(*)::VARCHAR FROM core.analysis_panel_balanced);

SELECT * FROM core.coverage_summary;
