-- A4. The ten most expensive census tracts, by the price of the property bought.
-- Property value rather than loan amount: a large loan in a cheap area and a
-- small loan in an expensive one are indistinguishable on loan size alone.
-- Originated loans only, since a valuation exists on a loan that completed.
-- A tract code carries its county in the first five digits, which is how the
-- county name is joined without going through the fact table's own county code.
SELECT f.census_tract,
       c.county_name,
       count(*)                                                      AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS numeric))                                            AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS numeric))                                            AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands * 1000)
             AS numeric))                                            AS median_applicant_income
FROM marts.fct_application f
LEFT JOIN ref.ref_county c ON c.county_code = left(f.census_tract, 5)
WHERE f.action_taken = '1'
  AND f.property_value IS NOT NULL
  AND f.census_tract <> 'UNKNOWN'
GROUP BY 1, 2
HAVING count(*) >= 100
ORDER BY 4 DESC, 1
LIMIT 10;
