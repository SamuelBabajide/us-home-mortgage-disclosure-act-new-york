-- General analysis section 0: the shape of the data, before any finding.
-- The first question a reader has is not "what did you find" but "what is in
-- here". This answers it in one screen: volume, money, and how many distinct
-- things of each kind the register actually contains.
-- One pass computes the measures as a single row; a LATERAL VALUES join then
-- unpivots that row into a metric-and-value list, which reads far better on a
-- screen than one row of fourteen columns.
WITH f AS (
  SELECT count(*)                                                     AS rows_published,
         count(*) FILTER (WHERE action_taken <> '6')                  AS applications,
         count(*) FILTER (WHERE action_taken = '1')                   AS originated,
         count(*) FILTER (WHERE action_taken IN ('1','3'))            AS decided,
         sum(loan_amount) FILTER (WHERE action_taken = '1')           AS disbursed,
         percentile_disc(0.5) WITHIN GROUP (
           ORDER BY CASE WHEN action_taken = '1' THEN loan_amount END) AS median_loan,
         count(DISTINCT lei)                                          AS lenders,
         count(DISTINCT county_code)                                  AS counties,
         count(DISTINCT census_tract) FILTER (WHERE census_tract <> 'UNKNOWN') AS tracts,
         count(DISTINCT activity_year)                                AS years
  FROM marts.fct_application),
p AS (
  SELECT count(DISTINCT derived_sex)       AS sexes,
         count(DISTINCT derived_race)      AS races,
         count(DISTINCT derived_ethnicity) AS ethnicities,
         count(DISTINCT applicant_age)     AS age_bands
  FROM marts.dim_applicant_profile),
d AS (SELECT count(*) AS products FROM marts.dim_loan_product)
SELECT v.ord, v.metric, v.value
FROM f, p, d,
LATERAL (VALUES
  ( 1, 'rows published',                   CAST(f.rows_published AS numeric)),
  ( 2, 'applications (purchased excluded)', CAST(f.applications  AS numeric)),
  ( 3, 'decided applications',             CAST(f.decided        AS numeric)),
  ( 4, 'loans originated',                 CAST(f.originated     AS numeric)),
  ( 5, 'dollars disbursed',                CAST(f.disbursed      AS numeric)),
  ( 6, 'median originated loan, dollars',  CAST(f.median_loan    AS numeric)),
  ( 7, 'years covered',                    CAST(f.years          AS numeric)),
  ( 8, 'distinct lenders',                 CAST(f.lenders        AS numeric)),
  ( 9, 'distinct counties',                CAST(f.counties       AS numeric)),
  (10, 'distinct census tracts',           CAST(f.tracts         AS numeric)),
  (11, 'distinct loan products',           CAST(d.products       AS numeric)),
  (12, 'distinct applicant sex values',    CAST(p.sexes          AS numeric)),
  (13, 'distinct applicant race values',   CAST(p.races          AS numeric)),
  (14, 'distinct applicant ethnicity values', CAST(p.ethnicities AS numeric)),
  (15, 'distinct applicant age bands',     CAST(p.age_bands      AS numeric))
) AS v(ord, metric, value)
ORDER BY v.ord;
