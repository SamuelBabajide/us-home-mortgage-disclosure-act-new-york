-- C2b. Loan characteristics by applicant sex.
-- The characteristics of the loans that completed. Companion to C2a, which
-- carries the volume and outcome rates for the same groups.
-- Originated loans only, for the coverage reason set out in A2, and the count
-- is repeated as column 2 so every median has its denominator in view.
-- Columns run applicant, asset, loan, leverage, price, the order used in A2,
-- B2 and throughout.
-- Loan-to-value is the ratio as filed, which counts every lien on the property
-- rather than only the loan in the row. Section B sets out the test for this.
-- Loan-to-income is computed here; rows with zero or negative reported income
-- are excluded from that column alone.
-- The rate is pooled across four years in which the market median moved 237.5
-- basis points, so it partly reflects when a group borrowed. The orderings
-- below were checked within 2025 alone and hold.
SELECT a.derived_sex                                                            AS applicant_sex,
       count(*)                                                             AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                                 AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                                 AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                                 AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                              AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                              AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS DECIMAL(24,8)), 3)                                              AS median_interest_rate
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1'
GROUP BY 1
ORDER BY 2 DESC;
