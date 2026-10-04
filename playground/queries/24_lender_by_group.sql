-- Disparity analysis section 8: does the gap survive the lender?
-- The decided count here covers only applications where a race was reported, so
-- it is lower than the same lender's total decided count elsewhere in the phase.
-- Rates computed on a denominator that included unreported race would not be
-- comparable between the columns beside it.
WITH d AS (
  SELECT i.institution_name AS lender, f.action_taken, a.derived_race,
         CASE WHEN a.derived_race = 'White' THEN 'W' ELSE 'O' END AS grp
  FROM marts.fct_application f
  JOIN marts.dim_institution i
    ON i.activity_year = f.activity_year AND i.lei = f.lei
  JOIN marts.dim_applicant_profile a
    ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3')
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only'))
SELECT lender, count(*) AS decided,
  round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='W')
        /nullif(count(*) FILTER (WHERE grp='W'),0), 1) AS white,
  round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='O')
        /nullif(count(*) FILTER (WHERE grp='O'),0), 1) AS all_other,
  round(100.0*count(*) FILTER (WHERE action_taken='3'
                               AND derived_race='Black or African American')
        /nullif(count(*) FILTER (WHERE derived_race='Black or African American'),0), 1) AS black,
  round(100.0*count(*) FILTER (WHERE action_taken='3' AND derived_race='Asian')
        /nullif(count(*) FILTER (WHERE derived_race='Asian'),0), 1) AS asian
FROM d GROUP BY 1 ORDER BY 2 DESC LIMIT 6;
