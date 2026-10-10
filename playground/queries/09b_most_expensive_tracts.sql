-- General analysis section 7: the most expensive neighbourhoods in the state.
-- Property value is the price of the house, so it answers "where is the
-- expensive property", which the loan amount on its own does not: a large loan
-- in a cheap area and a small loan in an expensive one look alike.
-- Originated loans only, since a property value exists on a loan that was made,
-- and a tract needs 100 of them to appear, so one mansion cannot carry a tract.
-- The metro name is taken with max() because a tract keeps the same metro in
-- every year, and that lets the result group by tract alone.
SELECT f.census_tract,
       max(m.msa_md_name)                                           AS metro_area,
       count(*)                                                     AS loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS numeric))                                           AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS numeric))                                           AS median_loan,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands)
             AS numeric))                                           AS median_income_k
FROM marts.fct_application f
LEFT JOIN marts.dim_msa m
  ON m.activity_year = f.activity_year AND m.msa_md = f.msa_md
WHERE f.action_taken = '1'
  AND f.property_value IS NOT NULL
  AND f.census_tract <> 'UNKNOWN'
GROUP BY 1
HAVING count(*) >= 100
ORDER BY 4 DESC, 1
LIMIT 10;
