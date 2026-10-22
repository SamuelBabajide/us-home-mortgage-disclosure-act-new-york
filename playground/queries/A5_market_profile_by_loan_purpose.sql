-- Market profile by loan purpose.
-- The same shape as A4, cut by the six purposes HMDA defines.
-- Here the two share columns come apart, and that gap is the most useful thing
-- in the table. Home purchase is 45.92 percent of applications and 53.31 percent
-- of originated loans; home improvement is 15.51 and 12.90; other purpose is
-- 12.25 and 9.35. The categories do not complete at the same rate, so the market
-- that gets made is a different shape from the market that gets asked for.
-- Reading the two columns together gives that difference without a seventh
-- column: where share of originations exceeds share of applications, the purpose
-- completes above the market average, and where it falls short it completes
-- below.
-- Median loan amount and total loan amount are on originated loans only, for
-- the coverage reason in A2.
-- Labels come from ref.ref_code rather than being written into the query.
SELECT r.label                                                              AS loan_purpose,
       count(*)                                                            AS total_applications,
       round(CAST(100.0 * count(*) AS DECIMAL(24,8))
             / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 2)            AS pct_of_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                        AS originated_loans,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                           AS pct_of_originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_amount END)
             AS numeric))                                                  AS median_loan_amount,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)  AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code r
  ON r.code_field = 'loan_purpose'
 AND r.code_value = p.loan_purpose
WHERE f.action_taken <> '6'
GROUP BY r.label
ORDER BY 2 DESC;
