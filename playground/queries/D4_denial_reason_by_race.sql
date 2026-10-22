-- Denial reason by applicant race, as a rate.
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
           count(*) FILTER (WHERE a.derived_race = 'White')                                     AS apps_white,
           count(*) FILTER (WHERE a.derived_race = 'Black or African American')                 AS apps_black,
           count(*) FILTER (WHERE a.derived_race = 'Asian')                                     AS apps_asian,
           count(*) FILTER (WHERE a.derived_race = 'American Indian or Alaska Native')          AS apps_amer_indian,
           count(*) FILTER (WHERE a.derived_race = 'Native Hawaiian or Other Pacific Islander') AS apps_nhpi,
           count(*) FILTER (WHERE a.derived_race = '2 or more minority races')                  AS apps_two_or_more,
           count(*) FILTER (WHERE a.derived_race = 'Joint')                                     AS apps_joint,
           count(*) FILTER (WHERE a.derived_race = 'Free Form Text Only')                       AS apps_free_form,
           count(*) FILTER (WHERE a.derived_race = 'Race Not Available')                        AS apps_race_not_available
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           a.derived_race AS grp
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
SELECT COALESCE(d.denial_reason, 'All reasons')               AS denial_reason,
       count(*)              AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'White') AS DECIMAL(24,8))
             / CAST(max(n.apps_white) AS DECIMAL(24,8)), 2)              AS white_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Black or African American') AS DECIMAL(24,8))
             / CAST(max(n.apps_black) AS DECIMAL(24,8)), 2)              AS black_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Asian') AS DECIMAL(24,8))
             / CAST(max(n.apps_asian) AS DECIMAL(24,8)), 2)              AS asian_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'American Indian or Alaska Native') AS DECIMAL(24,8))
             / CAST(max(n.apps_amer_indian) AS DECIMAL(24,8)), 2)        AS amer_indian_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Native Hawaiian or Other Pacific Islander') AS DECIMAL(24,8))
             / CAST(max(n.apps_nhpi) AS DECIMAL(24,8)), 2)               AS nhpi_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '2 or more minority races') AS DECIMAL(24,8))
             / CAST(max(n.apps_two_or_more) AS DECIMAL(24,8)), 2)        AS two_or_more_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Joint') AS DECIMAL(24,8))
             / CAST(max(n.apps_joint) AS DECIMAL(24,8)), 2)              AS joint_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Free Form Text Only') AS DECIMAL(24,8))
             / CAST(max(n.apps_free_form) AS DECIMAL(24,8)), 2)          AS free_form_per_100,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Race Not Available') AS DECIMAL(24,8))
             / CAST(max(n.apps_race_not_available) AS DECIMAL(24,8)), 2) AS race_not_available_per_100
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
