-- Disparity analysis section 10: the two outcomes that are not decisions.
-- The denominator here is all applications, not decided ones, because the whole
-- point is the outcomes that never reach a decision.
-- GROUPING SETS returns the per-group rows and the combined comparison row from
-- one pass. The HAVING keeps the combined row and drops the two grouping rows
-- that would merely restate a row the per-group grouping already produced.
WITH d AS (
  SELECT f.action_taken, a.derived_race,
         CASE WHEN a.derived_race = 'White' THEN 'White'
              WHEN a.derived_race IN ('Race Not Available','Free Form Text Only')
                   THEN 'Race not reported'
              ELSE 'All other reported races combined' END AS grp
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk)
SELECT coalesce(derived_race, grp) AS applicant_group,
       count(*)                   AS applications,
       round(100.0*count(*) FILTER (WHERE action_taken = '5')/count(*), 1) AS closed_incomplete_pct,
       round(100.0*count(*) FILTER (WHERE action_taken = '4')/count(*), 1) AS withdrawn_pct
FROM d
GROUP BY GROUPING SETS ((derived_race), (grp))
HAVING derived_race IS NOT NULL
    OR grp = 'All other reported races combined'
ORDER BY (derived_race IS NULL), 2 DESC;
