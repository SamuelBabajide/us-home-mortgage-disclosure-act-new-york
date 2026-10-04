-- Disparity analysis section 10.1: the reason given for a denial, by group.
-- reason_ordinal = 1 takes the primary reason only, because HMDA allows up to
-- four and counting all of them would make the shares sum past 100.
-- Compositional, not causal: it describes what denied applicants were told,
-- which is not evidence about how any criterion was applied.
SELECT a.derived_race AS applicant_group,
       count(*)       AS denials_with_reason,
  round(100.0*count(*) FILTER (WHERE v.denial_reason = 'Debt-to-income ratio')
        /count(*), 1) AS dti_pct,
  round(100.0*count(*) FILTER (WHERE v.denial_reason = 'Credit history')
        /count(*), 1) AS credit_history_pct,
  round(100.0*count(*) FILTER (WHERE v.denial_reason = 'Collateral')
        /count(*), 1) AS collateral_pct
FROM marts.v_denial_reason v
JOIN marts.fct_application f
  ON f.activity_year = v.activity_year AND f.application_sk = v.application_sk
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE v.reason_ordinal = 1 AND f.action_taken = '3'
  AND a.derived_race <> 'Free Form Text Only'
GROUP BY 1 ORDER BY 2 DESC;
