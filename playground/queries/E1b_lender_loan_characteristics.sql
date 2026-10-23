-- Lender performance, loan characteristics.
-- Originated loans only, for the coverage reason in A2: a denied application
-- has no interest rate and often no property value, so a median taken over
-- every application would be a median of whatever happened to be filled in.
-- Total applications is kept beside originated loans so the funnel behind the
-- medians stays visible, and so a median is always read beside its count.
-- Medians use percentile_disc, which returns a figure a borrower actually paid
-- rather than a midpoint between two of them, and is exact in both engines.
-- The column order is the one used in A2, B2, C1b and C4b.
-- Both income columns exclude rows reporting zero or negative income.
-- Every lender in the register is returned, 1,139 of them. There is no filter on
-- where a lender is headquartered: 221 are in New York and 918 are not. The only
-- filter is on the applications, which are all in New York.
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
       count(*)                                                          AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                       AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' AND f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                          AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.property_value END)
             AS DECIMAL(24,8)))                                          AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_amount END)
             AS DECIMAL(24,8)))                                          AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_to_value_ratio END)
             AS DECIMAL(24,8)), 2)                                       AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' AND f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                       AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)                                       AS median_interest_rate
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 2 DESC, l.lei;
