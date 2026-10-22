-- Denial reason by applicant sex, as a rate.
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
           count(*) FILTER (WHERE a.derived_sex = 'Male')              AS apps_male,
           count(*) FILTER (WHERE a.derived_sex = 'Female')            AS apps_female,
           count(*) FILTER (WHERE a.derived_sex = 'Joint')             AS apps_joint,
           count(*) FILTER (WHERE a.derived_sex = 'Sex Not Available') AS apps_sex_not_available
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           a.derived_sex AS grp
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
SELECT COALESCE(d.denial_reason, 'All reasons')              AS denial_reason,
       count(*)             AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Male') AS DECIMAL(24,8))
             / CAST(max(n.apps_male) AS DECIMAL(24,8)), 2)              AS male_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Female') AS DECIMAL(24,8))
             / CAST(max(n.apps_female) AS DECIMAL(24,8)), 2)            AS female_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Joint') AS DECIMAL(24,8))
             / CAST(max(n.apps_joint) AS DECIMAL(24,8)), 2)             AS joint_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Sex Not Available') AS DECIMAL(24,8))
             / CAST(max(n.apps_sex_not_available) AS DECIMAL(24,8)), 2) AS sex_not_available_per_100
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
