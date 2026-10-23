-- Denial reason by loan purpose, as a rate.
-- Each cell is the number of times this reason was cited for this group per 100
-- applications the group filed, purchased loans excluded. Every column carries
-- its own denominator, so the size of a group cannot leak into the cell.
-- The denominator is the one A1 uses for the denial rate, which makes each
-- column total equal that group's denial rate times its reasons per denial.
-- The unit is a reason citation. HMDA allows up to four per denial, so the
-- 320,762 denied applications carry 411,362 citations. No application cites the
-- same reason twice, so a citation and an application citing it are one count.
-- ref.ref_code repeats the nine labels once per reason slot, so the join is
-- pinned to denial_reason_1 to avoid a fourfold fan-out. Code 1111 is the
-- partially exempt filer code and has no label there.
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE p.loan_purpose = '1')  AS apps_home_purchase,
           count(*) FILTER (WHERE p.loan_purpose = '31') AS apps_refinancing,
           count(*) FILTER (WHERE p.loan_purpose = '32') AS apps_cash_out_refi,
           count(*) FILTER (WHERE p.loan_purpose = '2')  AS apps_home_improvement,
           count(*) FILTER (WHERE p.loan_purpose = '4')  AS apps_other_purpose,
           count(*) FILTER (WHERE p.loan_purpose = '5')  AS apps_not_applicable
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           p.loan_purpose AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')             AS denial_reason,
       count(*)            AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '1') AS DECIMAL(24,8))
             / CAST(max(n.apps_home_purchase) AS DECIMAL(24,8)), 2)    AS home_purchase,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '31') AS DECIMAL(24,8))
             / CAST(max(n.apps_refinancing) AS DECIMAL(24,8)), 2)      AS refinancing,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '32') AS DECIMAL(24,8))
             / CAST(max(n.apps_cash_out_refi) AS DECIMAL(24,8)), 2)    AS cash_out_refi,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '2') AS DECIMAL(24,8))
             / CAST(max(n.apps_home_improvement) AS DECIMAL(24,8)), 2) AS home_improvement,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '4') AS DECIMAL(24,8))
             / CAST(max(n.apps_other_purpose) AS DECIMAL(24,8)), 2)    AS other_purpose,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '5') AS DECIMAL(24,8))
             / CAST(max(n.apps_not_applicable) AS DECIMAL(24,8)), 2)   AS not_applicable
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
