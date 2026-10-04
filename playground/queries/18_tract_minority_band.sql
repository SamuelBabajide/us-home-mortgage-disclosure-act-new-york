-- Disparity analysis section 7, the weaker of the two geography tests: denial
-- against the minority share of the census tract. Consistent with either
-- explanation on its own, because applicants are not randomly distributed
-- across tracts, which is why query 18b compares within a single tract.
WITH d AS (
  SELECT f.action_taken, t.minority_population_pct,
         CASE WHEN t.minority_population_pct <  20 THEN 'under 20%'
              WHEN t.minority_population_pct <  40 THEN '20 to 40%'
              WHEN t.minority_population_pct <  60 THEN '40 to 60%'
              WHEN t.minority_population_pct <  80 THEN '60 to 80%'
              ELSE                                       '80% and above'
         END AS minority_band
  FROM marts.fct_application f
  JOIN marts.dim_tract t
    ON t.activity_year = f.activity_year AND t.census_tract = f.census_tract
  WHERE f.action_taken IN ('1','3')
    AND f.census_tract <> 'UNKNOWN'
    AND t.minority_population_pct IS NOT NULL)
SELECT minority_band AS tract_minority_population,
       count(*)      AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3')/count(*), 1) AS denial_rate
FROM d GROUP BY 1 ORDER BY min(minority_population_pct);
