-- Disparity analysis section 5: the same five income bands, with the groups
-- collapsed to White against all other reported races, and the gap in points.
-- The bands are ordered by the lowest income in each one rather than
-- alphabetically, so the labels can read the way a person would write them.
WITH d AS (
  SELECT f.action_taken, f.income_thousands,
         CASE WHEN a.derived_race = 'White' THEN 'W' ELSE 'O' END AS grp,
         CASE WHEN f.income_thousands <  50 THEN 'under 50k'
              WHEN f.income_thousands < 100 THEN '50k to 100k'
              WHEN f.income_thousands < 150 THEN '100k to 150k'
              WHEN f.income_thousands < 200 THEN '150k to 200k'
              ELSE                               '200k and above' END AS band
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
    AND f.income_thousands IS NOT NULL
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only'))
SELECT applicant_income, white_decided, other_decided,
       white, all_other_reported_races,
       round(all_other_reported_races - white, 1) AS gap
FROM (
  SELECT band                              AS applicant_income,
         min(income_thousands)              AS band_floor,
         count(*) FILTER (WHERE grp='W')    AS white_decided,
         count(*) FILTER (WHERE grp='O')    AS other_decided,
         round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='W')
               /nullif(count(*) FILTER (WHERE grp='W'),0), 1) AS white,
         round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='O')
               /nullif(count(*) FILTER (WHERE grp='O'),0), 1) AS all_other_reported_races
  FROM d GROUP BY 1) s
ORDER BY band_floor;
