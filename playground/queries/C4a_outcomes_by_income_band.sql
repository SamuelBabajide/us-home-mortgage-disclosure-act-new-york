WITH application AS (
    SELECT f.action_taken,
           f.loan_amount,
           f.income_thousands,
           f.property_value,
           f.interest_rate,
           f.loan_to_value_ratio,
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
    WHERE f.action_taken <> '6'
),
band_label (band_key, income_band) AS (
    VALUES (1, 'Under 50k'),    (2, '50k to 74k'),   (3, '75k to 99k'),
           (4, '100k to 149k'), (5, '150k to 199k'), (6, '200k to 299k'),
           (7, '300k and over'), (8, 'Income not reported')
)
SELECT l.income_band,
       count(*)                                                                   AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS denial_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS incomplete_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS withdrawal_rate,
       count(*) FILTER (WHERE a.action_taken = '1')                               AS originated_loans,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE a.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                                  AS originated_share_pct,
       sum(a.loan_amount) FILTER (WHERE a.action_taken = '1')                     AS total_loan_amount
FROM application a
JOIN band_label l ON l.band_key = a.band_key
GROUP BY a.band_key, l.income_band
ORDER BY a.band_key;
