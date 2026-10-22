-- Lender geographic reach.
-- One row per lender, with the number of distinct census tracts in which it
-- made at least one originated loan. A census tract is a neighbourhood of a few
-- thousand people; A3 counts 5,281 of them in the New York data, which is the
-- figure a lender's count is read against.
-- No spread by tract: 5,281 columns is not a table. The count is the summary of
-- that spread, and it answers the question the spread would: how much of the
-- state does this lender actually lend in.
-- Tracts are counted on originated loans only, so the column measures where a
-- lender lent rather than where it took applications.
-- 'UNKNOWN' is excluded from both the numerator and the denominator. 3,373
-- originated loans across 67 lenders carry it, and counting it would hand each
-- of those lenders a phantom tract. A3 excludes it the same way, which is why
-- the denominator comes out at the 5,281 A3 publishes.
-- The denominator is a scalar subquery rather than a literal, so the coverage
-- column cannot drift from A3 if the data is reloaded.
-- Loans per tract is the density behind the coverage figure and is the column
-- that separates a regional lender dense in its own territory from a statewide
-- originator thin everywhere. Lenders with no originated loans return null
-- rather than zero, because nothing divided by no tracts is not a density.
-- Every lender in the register is returned, 1,139 of them. There is no filter on
-- where a lender is headquartered: 221 are in New York and 918 are not.
WITH lender AS (
    -- Two separate name problems, both fixed here so all three queries share one
    -- definition of what a lender is.
    -- First, the register files an institution name per year, and 1,279 LEIs
    -- carry more than one spelling across the four years, almost all of them
    -- differences of case or punctuation. Joining the dimension year by year
    -- would split one lender into several rows, so one name is taken per LEI:
    -- the most recent year's, with the name itself as a stable tie-break.
    -- Second, a name is not an identifier. Nine names in the New York data are
    -- shared by two LEIs. Six are unrelated banks that happen to share a name,
    -- FIRST BANK of Burkburnett TX and FIRST BANK of Hamilton NJ, Five Star Bank
    -- of Warsaw NY and Five Star Bank of Rancho Cordova CA, and grouping on the
    -- name would silently merge them. Three are one institution filing under two
    -- LEIs from the same city, where even the city does not separate them.
    -- So the grain is the LEI, and the label is widened only as far as it has to
    -- be: the city and state where the name alone is ambiguous, and the LEI
    -- itself where the city does not settle it either. Every one of the 1,139
    -- rows is then one filer with one label.
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                            AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                         AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)  AS total_loan_amount,
       count(DISTINCT CASE WHEN f.action_taken = '1' AND f.census_tract <> 'UNKNOWN'
                           THEN f.census_tract END)                         AS census_tracts,
       round(CAST(100.0 * count(DISTINCT CASE WHEN f.action_taken = '1' AND f.census_tract <> 'UNKNOWN'
                                              THEN f.census_tract END) AS DECIMAL(24,8))
             / CAST((SELECT count(DISTINCT census_tract)
                     FROM marts.fct_application
                     WHERE census_tract <> 'UNKNOWN') AS DECIMAL(24,8)), 2) AS tract_coverage_pct,
       round(CAST(count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / CAST(NULLIF(count(DISTINCT CASE WHEN f.action_taken = '1' AND f.census_tract <> 'UNKNOWN'
                                               THEN f.census_tract END), 0) AS DECIMAL(24,4)), 1)
                                                                           AS loans_per_tract
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC;
