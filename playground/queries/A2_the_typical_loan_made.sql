-- A2. Overall market KPIs: the typical loan that was actually made.
-- Originated loans only. Interest rate and loan-to-value are present on 96
-- percent of originations but only 60 and 78 percent of all applications,
-- because a rate and a valuation are set when a loan completes.
-- Columns run applicant, then asset, then loan, then leverage, then price.
SELECT count(*)                                                        AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN income_thousands * 1000 END)
             AS numeric))                                              AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY property_value)
             AS numeric))                                              AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_amount)
             AS numeric))                                              AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_to_value_ratio)
             AS numeric), 2)                                           AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN loan_amount / (income_thousands * 1000) END)
             AS numeric), 2)                                           AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY interest_rate)
             AS numeric), 3)                                           AS median_interest_rate
FROM marts.fct_application
WHERE action_taken = '1';
