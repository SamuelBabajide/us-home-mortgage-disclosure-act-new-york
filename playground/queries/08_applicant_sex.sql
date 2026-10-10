-- General analysis section 11: the applicant sex funnel.
-- Purchased loans are excluded, as in every funnel in this phase: nobody
-- applied for those.
-- Joint is not a sex. HMDA assigns it when two applicants of different sexes
-- apply together, so it is kept as its own row rather than merged or dropped,
-- and the single-applicant comparison is Male against Female.
SELECT a.derived_sex                                                 AS applicant_sex,
       count(*)                                                      AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
             / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1)      AS pct_of_applications,
       count(*) FILTER (WHERE f.action_taken IN ('1','2'))           AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 1)                   AS approval_rate,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                            AS median_approved,
       round(CAST(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                                        AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY 1 ORDER BY 2 DESC;
