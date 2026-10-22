-- Lender share of originations by loan purpose.
-- One row per lender. Columns 2 to 4 are the lender's own book. After them each
-- purpose gets a pair: the lender's loans in it as a share of that lender's own
-- originated loans, and the dollars behind them as an amount.
-- The denominator is the lender's OWN originated loans, column 3, not the
-- market's. So a row describes that lender's product mix and the share columns
-- sum to 100 across each row rather than down the column. The amount columns
-- sum to column 4 on every row, exactly, because they are sums rather than
-- quotients.
-- The count behind any share is recoverable as share / 100 x column 3, so
-- nothing is lost by showing a proportion. The dollars are not recoverable from
-- anything, which is why those stay absolute.
-- Market share is deliberately absent here: it lives in E1a, on both a loan
-- count and a loan amount basis. A lender's share of any single purpose is
-- (this share x E1a's loan-count market share) divided by that purpose's own
-- share of the market, which Sections A, C and D publish.
-- Two decimal places. The smallest non-zero cell a large lender can have is one
-- loan in twelve thousand, which prints as 0.01; only a lender above twenty
-- thousand originations can round a single loan away, and there are ten.
-- A lender with no originated loans at all, and there are 220, returns null on
-- every share rather than zero: it has no mix. Its amounts are 0, because zero
-- dollars is a fact while an undefined proportion is not.
-- A lender with nothing in one purpose gets a 0.00 share and 0 dollars.
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
       count(*)                 AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')               AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)              AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '1') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS home_purchase_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '1'), 0)    AS home_purchase_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '31') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)        AS refinancing_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '31'), 0)      AS refinancing_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '32') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS cash_out_refi_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '32'), 0)    AS cash_out_refi_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '2') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS home_improvement_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '2'), 0) AS home_improvement_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '4') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS other_purpose_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '4'), 0)    AS other_purpose_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '5') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS not_applicable_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '5'), 0)   AS not_applicable_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC;
