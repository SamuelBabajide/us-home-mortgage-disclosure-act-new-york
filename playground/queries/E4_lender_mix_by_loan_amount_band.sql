-- Lender share of originations by loan amount band.
-- One row per lender. Columns 2 to 4 are the lender's own book. After them each
-- band gets a pair: the lender's loans in it as a share of that lender's own
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
-- count and a loan amount basis. A lender's share of any single band is
-- (this share x E1a's loan-count market share) divided by that band's own
-- share of the market, which Sections A, C and D publish.
-- Two decimal places. The smallest non-zero cell a large lender can have is one
-- loan in twelve thousand, which prints as 0.01; only a lender above twenty
-- thousand originations can round a single loan away, and there are ten.
-- A lender with no originated loans at all, and there are 220, returns null on
-- every share rather than zero: it has no mix. Its amounts are 0, because zero
-- dollars is a fact while an undefined proportion is not.
-- A lender with nothing in one band gets a 0.00 share and 0 dollars.
-- The six bands are round numbers placed on the actual distribution of
-- originated loans, whose quartiles are 115,000 and 485,000 dollars and whose
-- median is 245,000. Across the market they hold 19.23, 32.04, 25.01, 13.29,
-- 4.30 and 5.88 percent of originated loans.
-- The last column is a share with no amount beside it. 2,115 originated loans
-- across 144 lenders carry no loan amount at all, 227 of them at JPMorgan, so
-- without it the six size bands would quietly cover 99.78 percent of a
-- lender's originated loans rather than all of them. It has no amount column
-- because a loan with no amount contributes nothing to the dollars by
-- definition, so that column would read 0 on every row.
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
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount < 100000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS amt_under_100k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount < 100000), 0)   AS amt_under_100k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 100000 AND f.loan_amount < 250000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_100k_to_249k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 100000 AND f.loan_amount < 250000), 0) AS amt_100k_to_249k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 250000 AND f.loan_amount < 500000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_250k_to_499k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 250000 AND f.loan_amount < 500000), 0) AS amt_250k_to_499k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 500000 AND f.loan_amount < 750000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_500k_to_749k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 500000 AND f.loan_amount < 750000), 0) AS amt_500k_to_749k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 750000 AND f.loan_amount < 1000000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_750k_to_999k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 750000 AND f.loan_amount < 1000000), 0) AS amt_750k_to_999k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 1000000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)    AS amt_1m_and_over_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 1000000), 0)  AS amt_1m_and_over_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount IS NULL) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)  AS amt_not_reported_loans_pct
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
