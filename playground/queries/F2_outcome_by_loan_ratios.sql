-- Outcome by loan-to-income and loan-to-value, home purchase first liens only.
-- The restriction is the point of this query, not a convenience. Measured across
-- the whole register these two ratios appear to say that lower is better and
-- then contradict themselves at the bottom: applications at under one times
-- income are denied at 25.55 percent against 14.37 percent at two to three
-- times. That is not a borrower effect. Applications at under one times income
-- are 70.6 percent subordinate-lien and 66.4 percent home improvement or other
-- purpose, and D3 showed those purposes denied at 35 percent. The ratio was
-- reading the product.
-- Holding purpose and lien constant removes it. What survives is a shallow floor
-- and a steep right-hand tail, which is the finding this query exists to show.
-- Both measures are in one table, on one restricted population, so the two
-- cannot be compared across different filters by accident. A measure column
-- carries which ratio each row describes.
-- Rows with no reported income or no reported loan-to-value are kept as their
-- own band rather than dropped, for the usual reason.
WITH purchase AS (
    SELECT f.action_taken,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0        THEN 9
                WHEN f.loan_amount / (f.income_thousands * 1000) <  2             THEN 1
                WHEN f.loan_amount / (f.income_thousands * 1000) <  3             THEN 2
                WHEN f.loan_amount / (f.income_thousands * 1000) <  4             THEN 3
                WHEN f.loan_amount / (f.income_thousands * 1000) <  5             THEN 4
                WHEN f.loan_amount / (f.income_thousands * 1000) <  6             THEN 5
                ELSE 6
           END AS lti_key,
           CASE WHEN f.loan_to_value_ratio IS NULL                                THEN 9
                WHEN f.loan_to_value_ratio <=  70                                 THEN 1
                WHEN f.loan_to_value_ratio <=  80                                 THEN 2
                WHEN f.loan_to_value_ratio <=  90                                 THEN 3
                WHEN f.loan_to_value_ratio <=  95                                 THEN 4
                WHEN f.loan_to_value_ratio <= 100                                 THEN 5
                ELSE 6
           END AS ltv_key
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
      AND p.loan_purpose = '1'
      AND p.lien_status  = '1'
),
lti_label (band_key, band) AS (
    VALUES (1, 'under 2.0'), (2, '2.0 to under 3.0'), (3, '3.0 to under 4.0'),
           (4, '4.0 to under 5.0'), (5, '5.0 to under 6.0'), (6, '6.0 and over'),
           (9, 'income not reported')
),
ltv_label (band_key, band) AS (
    VALUES (1, 'up to 70%'), (2, 'over 70% to 80%'), (3, 'over 80% to 90%'),
           (4, 'over 90% to 95%'), (5, 'over 95% to 100%'), (6, 'over 100%'),
           (9, 'ratio not reported')
),
lti AS (
    SELECT 1 AS measure_order, 'loan to income' AS measure, p.lti_key AS band_key,
           count(*) AS total_applications,
           count(*) FILTER (WHERE p.action_taken IN ('1','2','8')) AS approved,
           count(*) FILTER (WHERE p.action_taken IN ('3','7'))     AS denied
    FROM purchase p GROUP BY 1, 2, 3
),
ltv AS (
    SELECT 2 AS measure_order, 'loan to value' AS measure, p.ltv_key AS band_key,
           count(*) AS total_applications,
           count(*) FILTER (WHERE p.action_taken IN ('1','2','8')) AS approved,
           count(*) FILTER (WHERE p.action_taken IN ('3','7'))     AS denied
    FROM purchase p GROUP BY 1, 2, 3
),
combined AS (
    SELECT l.measure_order, l.measure, lab.band, l.band_key, l.total_applications, l.approved, l.denied
    FROM lti l JOIN lti_label lab ON lab.band_key = l.band_key
    UNION ALL
    SELECT v.measure_order, v.measure, lab.band, v.band_key, v.total_applications, v.approved, v.denied
    FROM ltv v JOIN ltv_label lab ON lab.band_key = v.band_key
)
SELECT measure,
       band,
       total_applications,
       round(CAST(100.0 * total_applications AS DECIMAL(24,8))
             / CAST(sum(total_applications) OVER (PARTITION BY measure) AS DECIMAL(24,8)), 2)
                                                                        AS share_of_applications,
       round(CAST(100.0 * approved AS DECIMAL(24,8))
             / CAST(total_applications AS DECIMAL(24,8)), 2)            AS approval_rate,
       round(CAST(100.0 * denied AS DECIMAL(24,8))
             / CAST(total_applications AS DECIMAL(24,8)), 2)            AS denial_rate
FROM combined
ORDER BY measure_order, band_key;
