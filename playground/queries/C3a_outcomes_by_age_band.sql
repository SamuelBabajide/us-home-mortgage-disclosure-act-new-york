-- C3a. Applications and outcomes by applicant age band.
-- Volume and outcomes. The companion query C3b carries the medians for the
-- same groups, split out because one table of fifteen columns cannot be read
-- without scrolling and a table nobody can see is a table nobody checks.
-- The population changes once, after the four rates:
--   Columns 2 to 6, every application the group filed, purchased loans
--   excluded, on the denominators defined in A1. The four rates sum to 100
--   across each row.
--   Columns 7 to 9, the loans that completed. Share is the group's share of all
--   originated loans in the market, so it sums down the column, not across.
SELECT a.applicant_age                                                            AS applicant_age,
       count(*)                                                             AS total_applications,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS incomplete_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS withdrawal_rate,
       count(*) FILTER (WHERE f.action_taken = '1')                         AS originated_loans,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                            AS originated_share_pct,
       sum(f.loan_amount) FILTER (WHERE f.action_taken = '1')               AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY 1
ORDER BY 2 DESC;
