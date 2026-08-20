-- =============================================================================
-- analysis/rank_within_region.sql
--
-- Question : within each African region and round, where does a country sit on
--            trust in enforcement institutions, and how has that position moved?
-- Technique: RANK() and DENSE_RANK() with PARTITION BY, plus PERCENT_RANK for a
--            size-independent position (regions hold 4 to 14 countries, so raw
--            rank is not comparable across them).
-- Depends  : core.analysis_panel
--
-- RANK vs DENSE_RANK, since the difference is worth being able to state: on
-- tied values RANK leaves gaps (1,2,2,4) and DENSE_RANK does not (1,2,2,3).
-- With continuous weighted means exact ties are vanishingly rare here, so the
-- two agree in practice -- which is exactly why the choice must be reasoned
-- about rather than discovered.
--
-- Region comes from Afrobarometer's own COUNTRY.BY.REGION. NOTE: that
-- assignment is not stable -- Madagascar and Mauritius are Southern Africa in
-- R6/R7 and East Africa in R9. core.countries uses the most recent assignment
-- for all rounds, so a country does not appear to migrate mid-panel.
-- =============================================================================

CREATE OR REPLACE VIEW core.rank_within_region AS
SELECT region, round_number, country_name,
       n_valid_outcome,
       wmean_trust_index,
       RANK()         OVER w AS rank_in_region,
       DENSE_RANK()   OVER w AS dense_rank_in_region,
       COUNT(*)       OVER (PARTITION BY region, round_number) AS countries_in_region,
       ROUND(PERCENT_RANK() OVER w, 3) AS pct_rank_in_region,
       ROUND(wmean_trust_index
             - AVG(wmean_trust_index) OVER (PARTITION BY region, round_number), 3)
                                       AS gap_to_region_mean
FROM core.analysis_panel
WINDOW w AS (PARTITION BY region, round_number ORDER BY wmean_trust_index DESC)
ORDER BY region, round_number, rank_in_region;

-- Movement in within-region standing between consecutive observed rounds.
-- Restricted to adjacent rounds: a rank change across a skipped wave is not a
-- round-over-round movement.
CREATE OR REPLACE VIEW core.rank_movement AS
WITH r AS (
    SELECT region, country_name, round_number, rank_in_region, countries_in_region,
           LAG(rank_in_region)  OVER w AS prev_rank,
           LAG(round_number)    OVER w AS prev_round
    FROM core.rank_within_region
    WINDOW w AS (PARTITION BY country_name ORDER BY round_number)
)
SELECT region, country_name, prev_round, round_number, countries_in_region,
       prev_rank, rank_in_region,
       prev_rank - rank_in_region AS places_gained   -- positive = moved up
FROM r
WHERE prev_round IS NOT NULL AND round_number - prev_round = 1
ORDER BY places_gained DESC, region, country_name;
