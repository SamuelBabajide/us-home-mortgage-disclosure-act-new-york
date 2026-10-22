-- A3. Dataset coverage: how much of what this register contains.
-- One pass produces the counts; a LATERAL VALUES join unpivots that single row
-- into a metric and value list, which reads better than one row of eight
-- columns. Tracts exclude the UNKNOWN placeholder used where none was filed.
-- Counties are restricted to codes beginning 36, which is New York: the register
-- also carries an UNKNOWN code and three out-of-state codes totalling four rows.
WITH f AS (
  SELECT count(DISTINCT activity_year)                                 AS years_covered,
         count(DISTINCT lei)                                           AS lenders,
         count(DISTINCT CASE WHEN county_code LIKE '36%' THEN county_code END)  AS ny_counties,
         count(DISTINCT census_tract) FILTER (WHERE census_tract <> 'UNKNOWN') AS tracts
  FROM marts.fct_application),
p AS (SELECT count(DISTINCT loan_type)    AS loan_types,
             count(DISTINCT loan_purpose) AS loan_purposes
      FROM marts.dim_loan_product),
d AS (SELECT count(DISTINCT derived_sex)  AS sex_values,
             count(DISTINCT derived_race) AS race_values
      FROM marts.dim_applicant_profile)
SELECT v.ord, v.metric, v.value
FROM f, p, d,
LATERAL (VALUES
  (1, 'years covered',           CAST(f.years_covered  AS BIGINT)),
  (2, 'distinct lenders',        CAST(f.lenders        AS BIGINT)),
  (3, 'distinct New York counties', CAST(f.ny_counties AS BIGINT)),
  (4, 'distinct census tracts',  CAST(f.tracts         AS BIGINT)),
  (5, 'distinct loan types',     CAST(p.loan_types     AS BIGINT)),
  (6, 'distinct loan purposes',  CAST(p.loan_purposes  AS BIGINT)),
  (7, 'distinct sex values',     CAST(d.sex_values     AS BIGINT)),
  (8, 'distinct race values',    CAST(d.race_values    AS BIGINT))
) AS v(ord, metric, value)
ORDER BY v.ord;
