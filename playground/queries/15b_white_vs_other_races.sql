-- Disparity analysis section 4: the comparison a reader asks for first.
-- White against every other reported race combined, 2025. The two values that
-- carry no race information sit in a row of their own rather than being folded
-- into either side, because putting them on one side would turn the result into
-- a statement about who declined to answer.
WITH d AS (
  SELECT f.action_taken,
         CASE WHEN a.derived_race = 'White' THEN 'White'
              WHEN a.derived_race IN ('Race Not Available','Free Form Text Only')
                   THEN 'Race not reported'
              ELSE 'All other reported races' END AS grp
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025)
SELECT grp AS applicant_group, count(*) AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken = '3')/count(*), 1) AS denial_pct
FROM d GROUP BY 1 ORDER BY 3;
