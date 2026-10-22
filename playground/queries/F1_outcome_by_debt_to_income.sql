-- Outcome by debt-to-income band.
-- The single most actionable table in the project for an applicant, and the one
-- the denial reasons in Section D point straight at: debt-to-income is cited on
-- 32.87 percent of all denials, more than any other reason.
-- HMDA files this field two ways, which is why it needs normalising before use.
-- Outside the range 36 to 49 it arrives as a band string, '<20%', '20%-<30%',
-- '30%-<36%', '50%-60%', '>60%'. Inside that range it arrives as an exact
-- integer percentage. Grouping on the raw column would put 14 bands beside each
-- other on two different scales; the CASE puts them on one.
-- The band is not reported on 407,382 applications, and that row behaves
-- differently from every other: 47.59 percent withdrawal and 19.27 percent
-- incomplete. A debt-to-income ratio is computed during underwriting, so an
-- application that ended before underwriting has none. The row is kept because
-- it is a quarter of the register, and read as a stage rather than a ratio.
WITH banded AS (
    SELECT f.action_taken,
           CASE WHEN f.debt_to_income_band IS NULL                                  THEN 9
                WHEN f.debt_to_income_band = '<20%'                                 THEN 1
                WHEN f.debt_to_income_band = '20%-<30%'                             THEN 2
                WHEN f.debt_to_income_band = '30%-<36%'                             THEN 3
                WHEN f.debt_to_income_band IN ('36','37','38','39')                 THEN 4
                WHEN f.debt_to_income_band IN ('40','41','42','43','44')            THEN 5
                WHEN f.debt_to_income_band IN ('45','46','47','48','49')            THEN 6
                WHEN f.debt_to_income_band = '50%-60%'                              THEN 7
                WHEN f.debt_to_income_band = '>60%'                                 THEN 8
                ELSE 9
           END AS band_key
    FROM marts.fct_application f
    WHERE f.action_taken <> '6'
),
band_label (band_key, dti_band) AS (
    VALUES (1, 'Under 20%'),   (2, '20% to under 30%'), (3, '30% to under 36%'),
           (4, '36% to 39%'),  (5, '40% to 44%'),       (6, '45% to 49%'),
           (7, '50% to 60%'),  (8, 'Over 60%'),         (9, 'Not reported')
)
SELECT l.dti_band,
       count(*)                                                             AS total_applications,
       round(CAST(100.0 * count(*) AS DECIMAL(24,8))
             / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 2)             AS share_of_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE b.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE b.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE b.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS incomplete_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE b.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS withdrawal_rate
FROM banded b
JOIN band_label l ON l.band_key = b.band_key
GROUP BY b.band_key, l.dti_band
ORDER BY b.band_key;
