-- Market profile by loan type.
-- What the register contains, cut by the four loan types HMDA defines. One row
-- per type, covering every application and the loans that completed.
-- Two share columns, not one, and the pair is the point. Share of applications
-- is what the market asked for; share of originated loans is what it made. They
-- differ by however much the categories differ in how often they complete, so
-- reading them side by side gives the origination rate without a column for it.
-- On loan type the two shares sit within 0.33 of a point of each other on every
-- row, which is itself the finding: the four types complete at close to the same
-- rate, between 57.06 and 70.26 percent.
-- Median loan amount and total loan amount are on originated loans only, for
-- the coverage reason in A2: an application that was never made has no agreed
-- amount to take a median of.
-- The median uses percentile_disc, which returns an amount actually lent rather
-- than a midpoint between two, and is exact in both engines.
-- Labels come from ref.ref_code rather than being written into the query, so a
-- change to the regulator's wording arrives in one place.
SELECT r.label                                                              AS loan_type,
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
  ON r.code_field = 'loan_type'
 AND r.code_value = p.loan_type
WHERE f.action_taken <> '6'
GROUP BY r.label
ORDER BY 2 DESC;
