-- Lender outcomes on one product: conventional, first-lien home purchase.
-- Section E showed denial rates from 1.90 to 50.71 percent across the largest
-- lenders, and E1b showed that most of that was product mix rather than
-- decisions. This query removes the mix. Every row is the same product, so the
-- spread that remains is not explained by one lender writing second liens and
-- another writing first mortgages.
-- The floor of 2,000 applications on this one product is what makes the rates
-- stable enough to rank.
-- Columns 5 to 7 are here so a reader can test the obvious objection, that the
-- low-denial lenders simply receive stronger applications. They are the median
-- leverage, median loan-to-income and median applicant income of the
-- applications each lender received, decided ones only, so they describe the
-- queue rather than the outcome.
-- This is association, not cause. A lender's denial rate reflects who applies to
-- it as well as how it decides, and HMDA holds no credit score, so nothing here
-- isolates the decision. What it does establish is the size of the stakes.
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']' ELSE label END AS lender_name
    FROM (SELECT lei, label, count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name END AS label
                FROM (SELECT lei, institution_name, institution_city, institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei, i.institution_name, i.institution_city, i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                            AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2','3','7','8')
                            THEN f.loan_to_value_ratio END)
             AS numeric), 2)                                                AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2','3','7','8') AND f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS numeric), 2)                                                AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2','3','7','8') AND f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS numeric))                                                   AS median_applicant_income
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
WHERE f.action_taken <> '6'
  AND p.loan_purpose = '1'
  AND p.lien_status  = '1'
  AND p.loan_type    = '1'
GROUP BY l.lei, l.lender_name
HAVING count(*) >= 2000
ORDER BY denial_rate;
