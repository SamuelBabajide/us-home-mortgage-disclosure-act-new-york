-- Lender interest rate distribution.
-- One row per lender. Columns 5 to 9 are the interest rate at the tenth,
-- twenty-fifth, fiftieth, seventy-fifth and ninetieth percentile of the
-- lender's originated loans, which is the shape of its pricing rather than one
-- point from it.
-- percentile_disc, not percentile_cont: the continuous version interpolates
-- between two loans and returns a rate nobody paid, and the two engines land on
-- different sides of the third decimal. The discrete version returns a rate a
-- borrower actually paid and is exact in both. The median column reproduces
-- E1b's exactly.
-- The filter sits inside the ORDER BY as a CASE rather than in a WHERE clause,
-- so columns 2 to 4 still describe the lender's whole book.
-- Rates are pooled across four years in which the market median moved 237.5
-- basis points, so a percentile partly reflects when a lender was lending. It
-- also mixes first mortgages with second liens and open-end lines, which are
-- priced differently by design: see the mix table under E1b.
-- Column 4 is the denominator the five percentiles actually rest on, and it is
-- there because it is often not column 3. 34,269 originated loans, 3.6 percent,
-- carry no interest rate at all; three lenders with more than 1,000 originated
-- loans report no rate on any of them and return five blanks; and Pioneer Bank
-- reports 1,071 originated loans of which exactly one has a rate, so its five
-- percentiles are that one loan five times. Without column 4 that row looks
-- like a priced book of a thousand loans.
-- It counts the loans that HAVE a rate rather than the loans missing one,
-- because it is the denominator of the columns beside it, and every statistic
-- in this project is printed next to the count it rests on rather than next to
-- the count it does not. The missing figure is column 3 minus column 4.
-- 5,949 originated loans report a rate of exactly 0, mostly open-end lines in
-- subordinate position. They are counted as what they say they are: loans made
-- at a zero rate. A reported zero is a reported rate, not a missing value, and
-- the filer is the authority on what it filed. This is why EMPOWER FEDERAL
-- CREDIT UNION reads 0.000 at the tenth percentile, and the figure is correct.
-- Every median rate in the project treats them the same way, which is what
-- keeps the pooled market median at A2's published 6.281.
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
       count(*)                       AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')   AS originated_loans,
       count(f.interest_rate) FILTER (WHERE f.action_taken = '1') AS loans_with_rate,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS total_loan_amount,
       round(CAST(percentile_disc(0.10) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p10_interest_rate,
       round(CAST(percentile_disc(0.25) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p25_interest_rate,
       round(CAST(percentile_disc(0.50) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)AS median_interest_rate,
       round(CAST(percentile_disc(0.75) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p75_interest_rate,
       round(CAST(percentile_disc(0.90) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p90_interest_rate
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
