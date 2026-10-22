-- Denial reason by applicant age band, as a rate.
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
           count(*) FILTER (WHERE a.applicant_age = '<25')   AS apps_under_25,
           count(*) FILTER (WHERE a.applicant_age = '25-34') AS apps_age_25_to_34,
           count(*) FILTER (WHERE a.applicant_age = '35-44') AS apps_age_35_to_44,
           count(*) FILTER (WHERE a.applicant_age = '45-54') AS apps_age_45_to_54,
           count(*) FILTER (WHERE a.applicant_age = '55-64') AS apps_age_55_to_64,
           count(*) FILTER (WHERE a.applicant_age = '65-74') AS apps_age_65_to_74,
           count(*) FILTER (WHERE a.applicant_age = '>74')   AS apps_over_74,
           count(*) FILTER (WHERE a.applicant_age = '8888')  AS apps_age_not_provided
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           a.applicant_age AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')             AS denial_reason,
       count(*)            AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '<25') AS DECIMAL(24,8))
             / CAST(max(n.apps_under_25) AS DECIMAL(24,8)), 2)         AS under_25_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '25-34') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_25_to_34) AS DECIMAL(24,8)), 2)     AS age_25_to_34_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '35-44') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_35_to_44) AS DECIMAL(24,8)), 2)     AS age_35_to_44_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '45-54') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_45_to_54) AS DECIMAL(24,8)), 2)     AS age_45_to_54_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '55-64') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_55_to_64) AS DECIMAL(24,8)), 2)     AS age_55_to_64_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '65-74') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_65_to_74) AS DECIMAL(24,8)), 2)     AS age_65_to_74_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '>74') AS DECIMAL(24,8))
             / CAST(max(n.apps_over_74) AS DECIMAL(24,8)), 2)          AS over_74_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '8888') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_not_provided) AS DECIMAL(24,8)), 2) AS age_not_provided_per_100
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
