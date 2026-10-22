-- How much choice a borrower actually has, by what they are borrowing for.
-- A recommendation to compare lenders is only worth making if there are lenders
-- to compare, and that varies enormously by purpose. This counts them, and then
-- measures how much the choice is worth by the spread of denial rates among the
-- lenders large enough to rank.
-- lenders_active counts every lender that took an application for this purpose.
-- lenders_rankable counts those with at least 500, which is the floor at which a
-- denial rate is stable enough to compare. The p10 and p90 are taken across
-- those lenders' own denial rates, so the gap between them is the spread a
-- borrower is choosing between rather than the spread across all applications.
-- The percentiles are over lenders, not over applications, which is why they are
-- computed in a second pass: one lender is one observation regardless of size.
WITH by_lender AS (
    SELECT p.loan_purpose,
           f.lei,
           count(*)                                                AS apps,
           count(*) FILTER (WHERE f.action_taken IN ('3','7'))      AS denied
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
    GROUP BY 1, 2
),
rate AS (
    SELECT loan_purpose, lei, apps, denied,
           CAST(100.0 * denied AS DECIMAL(24,8)) / CAST(apps AS DECIMAL(24,8)) AS denial_rate
    FROM by_lender
),
purpose_label (loan_purpose, purpose) AS (
    VALUES ('1',  'Home purchase'),   ('31', 'Refinancing'),
           ('32', 'Cash-out refinancing'), ('2',  'Home improvement'),
           ('4',  'Other purpose'),   ('5',  'Not applicable')
)
SELECT l.purpose,
       sum(r.apps)                                                        AS total_applications,
       round(CAST(100.0 * sum(r.denied) AS DECIMAL(24,8))
             / CAST(sum(r.apps) AS DECIMAL(24,8)), 2)                     AS market_denial_rate,
       count(*)                                                           AS lenders_active,
       count(*) FILTER (WHERE r.apps >= 500)                              AS lenders_rankable,
       round(CAST(percentile_disc(0.10) WITHIN GROUP (
              ORDER BY CASE WHEN r.apps >= 500 THEN r.denial_rate END) AS numeric), 2)
                                                                          AS p10_lender_denial_rate,
       round(CAST(percentile_disc(0.50) WITHIN GROUP (
              ORDER BY CASE WHEN r.apps >= 500 THEN r.denial_rate END) AS numeric), 2)
                                                                          AS median_lender_denial_rate,
       round(CAST(percentile_disc(0.90) WITHIN GROUP (
              ORDER BY CASE WHEN r.apps >= 500 THEN r.denial_rate END) AS numeric), 2)
                                                                          AS p90_lender_denial_rate
FROM rate r
JOIN purpose_label l ON l.loan_purpose = r.loan_purpose
GROUP BY l.purpose
ORDER BY 2 DESC;
