-- =============================================================================
-- analysis/change_over_rounds.sql
--
-- Question : how does each country's weighted mean move from the previous round
--            it was surveyed in to this one?
-- Technique: LAG() OVER (PARTITION BY country ORDER BY round) -- round-over-round
--            change without a self-join, which is what LAG earns its place for.
-- Depends  : core.analysis_panel (analysis/panel_country_round.sql)
--
-- THE TRAP THIS QUERY AVOIDS. The panel is UNBALANCED: countries enter and
-- leave. LAG returns the previous ROW, not the previous ROUND, so for a country
-- surveyed in R6 and R9 but not R7 or R8, a naive LAG silently reports a
-- "round-over-round change" that actually spans seven years and two skipped
-- waves. prev_round and round_gap make that visible, and is_adjacent lets the
-- analysis restrict to genuine consecutive comparisons.
--
-- Fieldwork dates reinforce the point: rounds are WAVES, not years. R6 ran
-- 2014-03 to 2015-11 and R8 ran 2019-07 to 2021-07, so two countries in the
-- same round can be eighteen months apart.
-- =============================================================================

CREATE OR REPLACE VIEW core.change_over_rounds AS
WITH lagged AS (
    SELECT country_id, country_name, region, round_number,
           n_valid_outcome, wmean_trust_index, wmean_corruption_govt, wmean_govt_perf_economy,
           LAG(round_number)            OVER w AS prev_round,
           LAG(wmean_trust_index)       OVER w AS prev_trust_index,
           LAG(wmean_corruption_govt)   OVER w AS prev_corruption_govt,
           LAG(wmean_govt_perf_economy) OVER w AS prev_govt_perf,
           FIRST_VALUE(wmean_trust_index) OVER (
               PARTITION BY country_id ORDER BY round_number
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_trust_index,
           COUNT(*) OVER (PARTITION BY country_id) AS rounds_observed
    FROM core.analysis_panel
    WINDOW w AS (PARTITION BY country_id ORDER BY round_number)
)
SELECT country_id, country_name, region, round_number, prev_round,
       round_number - prev_round                       AS round_gap,
       (round_number - prev_round) = 1                 AS is_adjacent,
       rounds_observed,
       n_valid_outcome,
       wmean_trust_index,
       wmean_trust_index - prev_trust_index            AS d_trust_index,
       wmean_corruption_govt - prev_corruption_govt    AS d_corruption_govt,
       wmean_govt_perf_economy - prev_govt_perf        AS d_govt_perf_economy,
       wmean_trust_index - first_trust_index           AS cum_change_from_first
FROM lagged
ORDER BY country_name, round_number;

-- Non-adjacent comparisons, listed so the count is a reported fact rather than
-- something a reader has to reconstruct.
CREATE OR REPLACE VIEW core.non_adjacent_changes AS
SELECT country_name, prev_round, round_number, round_gap, d_trust_index
FROM core.change_over_rounds
WHERE prev_round IS NOT NULL AND NOT is_adjacent
ORDER BY round_gap DESC, country_name;
