-- Lender performance, outcomes.
-- One row per lender over the four years, purchased loans excluded, on the same
-- denominators A1 uses: the four rates cover every application the lender took
-- and sum to 100 across the row.
-- Every lender in the register is returned, 1,139 of them. There is no filter on
-- where a lender is headquartered: 221 are in New York and 918 are not. The only
-- filter is on the applications, which are all in New York.
-- Total applications is column 2 so that any row's rates are read beside the
-- count they rest on. Re-sorting by a rate puts the smallest lenders on top.
-- Columns 5 and 6 are the lender's market share on two bases: its originated
-- loans over all 951,371 in the register, and its dollars over all
-- 371,417,740,000. They are different questions and different numbers, because
-- a lender whose loans run bigger than the market's holds more of the money
-- than of the loans. Both denominators come from a window over the grouped
-- result, so each column sums to 100 down all 1,139 rows.
-- This is the only table in Section E that carries market share. E2 to E10 show
-- each lender's own product mix instead, and a lender's share of any single
-- category is (its share there x column 5) divided by that category's own share
-- of the market.
-- Four decimal places here, not two: the largest market share in the table is
-- 5.2483 percent and 977 lenders are below 0.1, so two places would collapse
-- most of the column to 0.00.
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
       count(*)                                                               AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                           AS originated_loans,
       sum(f.loan_amount) FILTER (WHERE f.action_taken = '1')                  AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 4)
                                                                              AS mkt_share_loans_pct,
       round(CAST(100.0 * COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8))
             / CAST(sum(COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)) OVER () AS DECIMAL(24,8)), 4)
                                                                              AS mkt_share_amount_pct,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS denial_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS incomplete_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS withdrawal_rate
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 2 DESC;
