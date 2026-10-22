-- A1. Overall market KPIs: volume, money and how applications end.
-- Denominator: every application filed, purchased loans excluded. A purchased
-- loan is one another lender already made and sold on, so nobody applied for it
-- here. The four rates are shares of that one denominator and sum to 100.
WITH a AS (SELECT * FROM marts.fct_application WHERE action_taken <> '6')
SELECT count(*)                                                        AS total_applications,
       count(*) FILTER (WHERE action_taken = '1')                      AS total_originated_loans,
       sum(loan_amount) FILTER (WHERE action_taken = '1')              AS total_loan_amount,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS approval_rate,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS denial_rate,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS incomplete_rate,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                     AS withdrawal_rate
FROM a;
