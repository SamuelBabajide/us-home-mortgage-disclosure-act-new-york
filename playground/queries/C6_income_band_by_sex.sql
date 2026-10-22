WITH banded AS (
    SELECT a.derived_sex          AS applicant_sex,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                WHEN f.income_thousands <  50 THEN 1
                WHEN f.income_thousands <  75 THEN 2
                WHEN f.income_thousands < 100 THEN 3
                WHEN f.income_thousands < 150 THEN 4
                WHEN f.income_thousands < 200 THEN 5
                WHEN f.income_thousands < 300 THEN 6
                ELSE 7
           END AS band_key
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
)
SELECT b.applicant_sex,
       count(*)                                                   AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 1) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)             AS pct_under_50k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 2) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_50k_to_74k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 3) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_75k_to_99k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 4) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_100k_to_149k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 5) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_150k_to_199k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 6) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_200k_to_299k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 7) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)         AS pct_300k_and_over,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 8) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_not_reported
FROM banded b
GROUP BY 1
ORDER BY 2 DESC;
