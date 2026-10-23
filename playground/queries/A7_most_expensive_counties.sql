-- A7. The ten most expensive counties, by the price of the property bought.
-- The same measure as A6, one level up. A county needs 500 originated loans to
-- appear, so the ranking is not decided by a handful of large sales in a small
-- county. The register also carries an UNKNOWN county code and three
-- out-of-state codes totalling four rows, which fall out of the join.
-- The register stores a county FIPS code and never a county name, so the 62 New
-- York names are supplied inline rather than joined from a reference table.
-- That is deliberate: it is a fixed, published list that cannot drift, it keeps
-- the query runnable anywhere the fact table is, and it puts the mapping in
-- front of the reader instead of behind a join. All 62 codes match, which is
-- also the check that the restriction to codes beginning 36 is complete.
WITH county (county_code, county_name) AS (
    VALUES ('36001', 'Albany County'),
           ('36003', 'Allegany County'),
           ('36005', 'Bronx County'),
           ('36007', 'Broome County'),
           ('36009', 'Cattaraugus County'),
           ('36011', 'Cayuga County'),
           ('36013', 'Chautauqua County'),
           ('36015', 'Chemung County'),
           ('36017', 'Chenango County'),
           ('36019', 'Clinton County'),
           ('36021', 'Columbia County'),
           ('36023', 'Cortland County'),
           ('36025', 'Delaware County'),
           ('36027', 'Dutchess County'),
           ('36029', 'Erie County'),
           ('36031', 'Essex County'),
           ('36033', 'Franklin County'),
           ('36035', 'Fulton County'),
           ('36037', 'Genesee County'),
           ('36039', 'Greene County'),
           ('36041', 'Hamilton County'),
           ('36043', 'Herkimer County'),
           ('36045', 'Jefferson County'),
           ('36047', 'Kings County'),
           ('36049', 'Lewis County'),
           ('36051', 'Livingston County'),
           ('36053', 'Madison County'),
           ('36055', 'Monroe County'),
           ('36057', 'Montgomery County'),
           ('36059', 'Nassau County'),
           ('36061', 'New York County'),
           ('36063', 'Niagara County'),
           ('36065', 'Oneida County'),
           ('36067', 'Onondaga County'),
           ('36069', 'Ontario County'),
           ('36071', 'Orange County'),
           ('36073', 'Orleans County'),
           ('36075', 'Oswego County'),
           ('36077', 'Otsego County'),
           ('36079', 'Putnam County'),
           ('36081', 'Queens County'),
           ('36083', 'Rensselaer County'),
           ('36085', 'Richmond County'),
           ('36087', 'Rockland County'),
           ('36089', 'St. Lawrence County'),
           ('36091', 'Saratoga County'),
           ('36093', 'Schenectady County'),
           ('36095', 'Schoharie County'),
           ('36097', 'Schuyler County'),
           ('36099', 'Seneca County'),
           ('36101', 'Steuben County'),
           ('36103', 'Suffolk County'),
           ('36105', 'Sullivan County'),
           ('36107', 'Tioga County'),
           ('36109', 'Tompkins County'),
           ('36111', 'Ulster County'),
           ('36113', 'Warren County'),
           ('36115', 'Washington County'),
           ('36117', 'Wayne County'),
           ('36119', 'Westchester County'),
           ('36121', 'Wyoming County'),
           ('36123', 'Yates County')
)
SELECT c.county_name,
       f.county_code,
       count(*)                                                      AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                      AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                      AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands * 1000)
             AS DECIMAL(24,8)))                                      AS median_applicant_income
FROM marts.fct_application f
JOIN county c ON c.county_code = f.county_code
WHERE f.action_taken = '1' AND f.property_value IS NOT NULL
GROUP BY 1, 2
HAVING count(*) >= 500
ORDER BY 4 DESC, 2
LIMIT 10;
