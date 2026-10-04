-- Disparity analysis section 3: the shift-share decomposition, per product.
-- Query 17 returns the two totals. This one shows the five rows they are made
-- of, so a reader can see which products moved the aggregate and in which
-- direction, rather than taking the summary on trust.
WITH y AS (
  SELECT f.activity_year AS yr, p.loan_purpose,
         count(*) FILTER (WHERE f.action_taken IN ('1','3')) AS decided,
         count(*) FILTER (WHERE f.action_taken = '3')        AS denied
  FROM marts.fct_application f
  JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
  WHERE f.activity_year IN (2022, 2023)
  GROUP BY 1,2),
t AS (SELECT yr, sum(decided) AS tot FROM y GROUP BY 1),
j AS (SELECT y.loan_purpose,
        max(CASE WHEN yr=2022 THEN 1.0*y.decided/t.tot    END) AS w22,
        max(CASE WHEN yr=2023 THEN 1.0*y.decided/t.tot    END) AS w23,
        max(CASE WHEN yr=2022 THEN 1.0*y.denied/y.decided END) AS r22,
        max(CASE WHEN yr=2023 THEN 1.0*y.denied/y.decided END) AS r23
      FROM y JOIN t USING (yr) GROUP BY 1)
SELECT c.label                            AS loan_purpose,
       round(100*j.w22, 1)                AS share_2022,
       round(100*j.w23, 1)                AS share_2023,
       round(100*j.r22, 1)                AS rate_2022,
       round(100*j.r23, 1)                AS rate_2023,
       round(100*(j.w23-j.w22)*j.r22, 3)  AS mix,
       round(100*j.w23*(j.r23-j.r22), 3)  AS within
FROM j
JOIN ref.ref_code c ON c.code_field = 'loan_purpose' AND c.code_value = j.loan_purpose
ORDER BY 7 DESC NULLS LAST, 1;
