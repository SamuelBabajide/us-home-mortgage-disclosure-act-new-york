-- Disparity analysis section 7, the stronger geography test: compare applicant
-- groups inside the same census tract, which holds the neighbourhood, the local
-- housing market and the local economy constant by construction rather than by
-- regression. A tract qualifies only when both sides reach 100 decisions, which
-- is why three of the smaller groups do not appear: no New York tract carries
-- 100 decided applications from them alongside 100 from White applicants.
WITH g AS (
  SELECT f.census_tract, a.derived_race AS grp,
         count(*)                                     AS decided,
         count(*) FILTER (WHERE f.action_taken = '3')  AS denied
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3')
    AND f.census_tract <> 'UNKNOWN'
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only')
  GROUP BY 1,2),
w AS (SELECT census_tract, decided AS white_decided,
             100.0*denied/decided AS rate_white
      FROM g WHERE grp = 'White'),
o AS (SELECT census_tract, grp, decided AS group_decided,
             100.0*denied/decided AS rate_group
      FROM g WHERE grp <> 'White'),
p AS (SELECT o.grp, o.rate_group - w.rate_white AS gap
      FROM o JOIN w ON w.census_tract = o.census_tract
      WHERE o.group_decided >= 100 AND w.white_decided >= 100)
SELECT grp                                             AS applicant_group,
       count(*)                                        AS tracts,
       count(*) FILTER (WHERE gap > 0)                 AS group_rate_higher,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY gap) AS numeric), 1) AS median_gap,
       round(CAST(min(gap) AS numeric), 1)             AS min_gap,
       round(CAST(max(gap) AS numeric), 1)             AS max_gap
FROM p
GROUP BY 1
ORDER BY 2 DESC, 1;
