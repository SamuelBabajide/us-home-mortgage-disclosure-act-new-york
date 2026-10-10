-- General analysis section 1: how concentrated is this market?
-- Share and running share are computed with window functions over the grouped
-- counts, so the denominator is every lender in the state rather than the ten
-- rows returned. LIMIT applies after the windows, which is what makes that work.
SELECT i.institution_name                                           AS lender,
       count(*)                                                     AS originations,
       round(100.0*count(*)/sum(count(*)) OVER (), 2)               AS pct_of_market,
       round(100.0*sum(count(*)) OVER (ORDER BY count(*) DESC, i.institution_name
                                       ROWS UNBOUNDED PRECEDING)
             /sum(count(*)) OVER (), 2)                             AS cumulative_pct
FROM marts.fct_application f
JOIN marts.dim_institution i
  ON i.activity_year = f.activity_year AND i.lei = f.lei
WHERE f.action_taken = '1'
GROUP BY 1
ORDER BY 2 DESC, 1
LIMIT 10;
