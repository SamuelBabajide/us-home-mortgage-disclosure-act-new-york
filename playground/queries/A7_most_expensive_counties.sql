-- A5. The ten most expensive counties, by the price of the property bought.
-- The same measure as A4, one level up. A county needs 500 originated loans to
-- appear, so the ranking is not decided by a handful of large sales in a small
-- county. County names come from ref.ref_county, a 62-row reference table of
-- New York county FIPS codes; the register also carries an UNKNOWN code and
-- three out-of-state codes totalling four rows, which fall out of the join.
SELECT c.county_name,
       f.county_code,
       count(*)                                                      AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS numeric))                                            AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS numeric))                                            AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands * 1000)
             AS numeric))                                            AS median_applicant_income
FROM marts.fct_application f
JOIN ref.ref_county c ON c.county_code = f.county_code
WHERE f.action_taken = '1' AND f.property_value IS NOT NULL
GROUP BY 1, 2
HAVING count(*) >= 500
ORDER BY 4 DESC, 1
LIMIT 10;
