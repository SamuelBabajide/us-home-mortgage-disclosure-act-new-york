-- B1. Market trend: volume, money and how applications end, by filing year.
-- The same measures and the same denominator as A1, split by activity_year.
-- Purchased loans are excluded, so the four rates share one denominator per
-- year and each year's four rates sum to 100.
SELECT activity_year,
       count(*)                                                        AS total_applications,
       count(*) FILTER (WHERE action_taken = '1')                      AS total_originated_loans,
       sum(loan_amount) FILTER (WHERE action_taken = '1')              AS total_loan_amount,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS approval_rate,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS denial_rate,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS incomplete_rate,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS withdrawal_rate
FROM marts.fct_application
WHERE action_taken <> '6'
GROUP BY 1
ORDER BY 1;
