-- Disparity analysis section 5: does income explain the gap?
-- Banding income and pivoting the bands into columns keeps every group on one
-- line. One pass over the fact table, no self-joins, two FILTER clauses per
-- cell: one counts the denials in the band, the other counts the band.
WITH d AS (
  SELECT f.action_taken, a.derived_race,
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
SELECT derived_race AS applicant_group, count(*) AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='under 50k')
             /nullif(count(*) FILTER (WHERE band='under 50k'),0), 1)      AS under_50k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='50k to 100k')
             /nullif(count(*) FILTER (WHERE band='50k to 100k'),0), 1)    AS b50_100k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='100k to 150k')
             /nullif(count(*) FILTER (WHERE band='100k to 150k'),0), 1)   AS b100_150k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='150k to 200k')
             /nullif(count(*) FILTER (WHERE band='150k to 200k'),0), 1)   AS b150_200k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='200k and above')
             /nullif(count(*) FILTER (WHERE band='200k and above'),0), 1) AS over_200k
FROM d GROUP BY 1 ORDER BY 2 DESC;
