-- B2. Market trend: the typical loan that was made, by filing year.
-- Originated loans only, for the coverage reason set out in A2. Columns run in
-- the same order as A2: applicant, asset, loan, leverage, price, so the two
-- tables can be read against each other without rereading the header.
SELECT activity_year,
       count(*)                                                        AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                        AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY property_value)
             AS DECIMAL(24,8)))                                        AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_amount)
             AS DECIMAL(24,8)))                                        AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                     AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN loan_amount / (income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                     AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY interest_rate)
             AS DECIMAL(24,8)), 3)                                     AS median_interest_rate
FROM marts.fct_application
WHERE action_taken = '1'
GROUP BY 1
ORDER BY 1;
