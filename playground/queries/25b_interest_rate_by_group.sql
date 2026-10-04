-- Disparity analysis section 11.1: the raw rate on the note, for contrast.
-- interest_rate adjusts for nothing, so this is restricted to 2025 to hold the
-- rate environment constant. It says something different from query 25, and the
-- disagreement between the two is the finding.
-- The median uses percentile_disc rather than percentile_cont. Mortgage rates and
-- rate spreads are quoted in eighths of a point, so interpolating between the two
-- middle loans of an even-sized group returns a price no borrower was charged.
-- It is also the one construct in this project where PostgreSQL and DuckDB can
-- legitimately disagree: interpolation is floating point, and on one group of 288
-- loans the two engines landed either side of the third decimal. percentile_disc
-- returns an observed value by position, so it is exact in both.
SELECT a.derived_race AS applicant_group,
       count(*)       AS loans,
       round(CAST(avg(f.interest_rate) AS numeric), 3) AS mean_rate_pct,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS numeric), 3)                       AS median_rate_pct
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1' AND f.interest_rate IS NOT NULL AND f.activity_year = 2025
GROUP BY 1 ORDER BY 4, 1;
