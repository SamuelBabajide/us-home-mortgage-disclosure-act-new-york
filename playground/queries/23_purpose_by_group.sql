-- Disparity analysis section 6: does the gap survive the product?
-- Loan purpose 5, "Not applicable", is excluded at 174 decided applications.
SELECT c.label                                                    AS loan_purpose,
       count(*)                                                   AS decided,
       round(100.0*count(*) FILTER (WHERE f.action_taken='3')
             /count(*), 1)                                        AS overall_denial,
       round(100.0*count(*) FILTER (WHERE f.action_taken='3'
                   AND a.derived_race='Black or African American')
             /nullif(count(*) FILTER (
                   WHERE a.derived_race='Black or African American'),0), 1)  AS black,
       round(100.0*count(*) FILTER (WHERE f.action_taken='3'
                   AND a.derived_race='White')
             /nullif(count(*) FILTER (WHERE a.derived_race='White'),0), 1)   AS white
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
JOIN ref.ref_code c ON c.code_field = 'loan_purpose' AND c.code_value = p.loan_purpose
WHERE f.action_taken IN ('1','3')
  AND p.loan_purpose <> '5'
GROUP BY 1 ORDER BY 5, 1;
