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
       count(*)                                                             AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN a.income_thousands > 0
                            THEN a.income_thousands * 1000 END)
             AS numeric))                                                   AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.property_value)
             AS numeric))                                                   AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.loan_amount)
             AS numeric))                                                   AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.loan_to_value_ratio)
             AS numeric), 2)                                                AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN a.income_thousands > 0
                            THEN a.loan_amount / (a.income_thousands * 1000) END)
             AS numeric), 2)                                                AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.interest_rate)
             AS numeric), 3)                                                AS median_interest_rate
FROM application a
JOIN band_label l ON l.band_key = a.band_key
WHERE a.action_taken = '1'
GROUP BY a.band_key, l.income_band
ORDER BY a.band_key;
