-- Disparity analysis section 11: price rather than access.
-- rate_spread is the gap between the loan's APR and the market benchmark for a
-- comparable loan, so it already adjusts for product, term and timing.
-- Originated loans only, because a loan that was never made has no price.
-- Mean and median together: a mean can be moved by a handful of extreme loans
-- and a median cannot, so agreement between them is itself evidence.
-- The median uses percentile_disc rather than percentile_cont. Mortgage rates and
-- rate spreads are quoted in eighths of a point, so interpolating between the two
-- middle loans of an even-sized group returns a price no borrower was charged.
-- It is also the one construct in this project where PostgreSQL and DuckDB can
-- legitimately disagree: interpolation is floating point, and on one group of 288
-- loans the two engines landed either side of the third decimal. percentile_disc
-- returns an observed value by position, so it is exact in both.
SELECT a.derived_race AS applicant_group,
       count(*)       AS originated_with_spread,
       round(CAST(avg(f.rate_spread) AS numeric), 3) AS mean_spread,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.rate_spread)
             AS numeric), 3)                         AS median_spread
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1' AND f.rate_spread IS NOT NULL
GROUP BY 1 ORDER BY 4, 1;
