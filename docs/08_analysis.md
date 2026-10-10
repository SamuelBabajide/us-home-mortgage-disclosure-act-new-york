# Phase 08: The analysis

What this market is, who borrows in it, what they borrow for, how much they get and what it costs them.

Every table below comes from a query you can run yourself. The query number links to the browser playground, which opens with that query loaded and already executed against all 1.75 million rows. If you think a number is wrong, you can check it in about ten seconds.

The outcome gaps between applicant groups, and what survives controlling for income, product, neighbourhood and lender, are a separate document: [phase 08b](08b_analysis_disparity.md).

---

## 0. What is actually in this register

Before any finding, the shape of the thing. A reader's first question is not what I
concluded but what the data contains, and nothing below means much without it.

Run live [▶ query 00](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=00)

```sql
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
```

| | metric | value |
|---|---|---|
| 1 | rows published | 1,754,846 |
| 2 | applications, purchased loans excluded | 1,596,676 |
| 3 | decided applications | 1,270,844 |
| 4 | loans originated | 951,371 |
| 5 | dollars disbursed | 371,417,740,000 |
| 6 | median originated loan, dollars | 245,000 |
| 7 | years covered | 4 |
| 8 | distinct lenders | 1,168 |
| 9 | distinct counties | 66 |
| 10 | distinct census tracts | 5,281 |
| 11 | distinct loan products | 194 |
| 12 | distinct applicant sex values | 4 |
| 13 | distinct applicant race values | 9 |
| 14 | distinct applicant ethnicity values | 5 |
| 15 | distinct applicant age bands | 8 |

**What this says.** 1,168 lenders made nearly a million loans across 5,281
neighbourhoods in four years, and 371 billion dollars changed hands. The three
row counts at the top are different denominators and they are not
interchangeable: 1.75 million is every row filed, 1.6 million is what somebody
actually applied for, and 1.27 million is what a lender said yes or no to. Each
table below says which one it uses.

The category counts matter for a different reason. Four sex values, nine race
values and five ethnicity values are not four, nine and five groups of people.
Each set includes codes for "not available" and for free-form text, and one sex
value is Joint, which describes an application rather than a person. Counting
them as though they were categories of applicant is the first mistake available
in this dataset.

---

## 1. Two decisions that come before every number

**Purchased loans are not applications.** 158,170 rows in this dataset have `action_taken = 6`, meaning the filer bought a loan another lender had already made. Nobody applied to anyone. Counting them in an application funnel is like counting a house you bought as a house you failed to build, and it does real damage: they are 70 percent of the rows where applicant age is unreported, and leaving them in made that band's approval rate read 19.9 percent instead of 66.9. Every funnel table in this document excludes them.

**Approved means the lender said yes.** That is `action_taken` 1, originated, plus 2, approved but not accepted. In the second case the lender approved and the applicant walked away, which is still an approval. *Total disbursed* is originated only, because that is money that actually left the building. The two differ by about one percentage point everywhere, and the definitions are stated on every table rather than assumed.

So the funnel in this document is: **applications → approved → disbursed.**

| | |
|---|---|
| Published rows | 1,755,419 |
| Modelled | 1,754,846 |
| Purchased loans, excluded from the funnel | 158,170 |
| **Applications** | **1,596,676** |
| Approved | 996,548 |
| Disbursed | 371.42bn |

---

## 2. Finding 1: the market lost a third of its volume and has not got it back

Run live [▶ query 01](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=01)

```sql
SELECT activity_year,
       count(*)                                          AS applications,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)  AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                            AS disbursed_bn
FROM marts.fct_application
WHERE action_taken <> '6'
GROUP BY 1 ORDER BY 1;
```

| year | applications | approved | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| 2022 | 500,553 | 321,416 | **64.2%** | 255,000 | 128.52bn |
| 2023 | 346,943 | 213,183 | 61.4% | 215,000 | 72.70bn |
| 2024 | 355,249 | 218,756 | 61.6% | 235,000 | 76.89bn |
| 2025 | 393,931 | 243,193 | 61.7% | 255,000 | 93.31bn |

Applications fell 31 percent in a single year and dollars fell 43 percent, which is the larger fall because the median loan shrank at the same time. By 2025 volume has recovered to 79 percent of 2022 and dollars to 73 percent.

**The approval rate is the part that did not recover.** It dropped 2.8 points in 2023 and has sat within 0.3 points of the new level for three years. Demand came back; the willingness to say yes did not. Phase 08b section 3 decomposes that move and shows it was products denying more rather than a change in what people applied for.

---

## 2.1 Finding 1b: no lender owns this market

Run live [▶ query 01b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=01b)

```sql
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
```

| lender | originations | share of market | running share |
|---|---|---|---|
| ROCKET MORTGAGE | 49,930 | 5.25% | 5.25% |
| United Wholesale Mortgage | 42,059 | 4.42% | 9.67% |
| JPMorgan Chase Bank, NA | 38,206 | 4.02% | 13.68% |
| CBNA Year to Date | 32,046 | 3.37% | 17.05% |
| M&T BANK | 30,030 | 3.16% | 20.21% |
| ESL Federal Credit Union | 23,170 | 2.44% | 22.65% |
| TD Bank | 19,709 | 2.07% | 24.72% |
| Premium Mortgage Corporation | 19,693 | 2.07% | 26.79% |
| WELLS FARGO BANK NA | 19,382 | 2.04% | 28.82% |
| CROSSCOUNTRY MORTGAGE, LLC | 18,196 | 1.91% | 30.74% |

**What this says.** The largest mortgage lender in New York State made one loan
in twenty. The ten largest together made under a third. The other 1,158 lenders
made the remaining 69 percent. For an industry people picture as a handful of
big banks, that is a far longer tail than expected, and it is the single most
useful fact about the structure of this market.

Two consequences run through the rest of the project. Any statement of the form
"banks do X" is describing more than a thousand independent institutions, so the
average hides enormous variation. And because no lender is large enough to move
the state aggregate on its own, a market-wide number is a genuine market
average rather than one firm's behaviour in disguise.

The share and running share are computed with window functions over the grouped
counts, so the denominator stays every lender in the state. `LIMIT` is applied
after the window, which is what lets ten rows report their share of 1,168.

## 3. Finding 2: nine tenths of this market is one product, and half the money is one purpose

Run live [▶ query 02](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=02)

```sql
-- General analysis section 2: which products carry this market.
SELECT c.label                                           AS loan_type,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code c ON c.code_field = 'loan_type' AND c.code_value = p.loan_type
WHERE f.action_taken <> '6'
GROUP BY 1 ORDER BY 2 DESC, 1;
```

| loan type | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Conventional | 1,434,757 | **89.9%** | 62.6% | 235,000 | 338.38bn |
| FHA insured | 123,790 | 7.8% | 60.0% | 285,000 | 25.44bn |
| VA guaranteed | 36,199 | 2.3% | 63.1% | 275,000 | 7.40bn |
| RHS or FSA guaranteed | 1,930 | 0.1% | 73.3% | 145,000 | 0.20bn |


Run live [▶ query 03](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=03)

```sql
-- General analysis section 2: purpose decides both approval and loan size.
SELECT c.label                                           AS loan_purpose,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code c ON c.code_field = 'loan_purpose' AND c.code_value = p.loan_purpose
WHERE f.action_taken <> '6'
GROUP BY 1 ORDER BY 2 DESC, 1;
```

| loan purpose | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Home purchase | 733,126 | 45.9% | **72.2%** | 345,000 | **240.49bn** |
| Home improvement | 247,663 | 15.5% | 51.9% | 85,000 | 15.94bn |
| Cash-out refinancing | 231,963 | 14.5% | 56.8% | 235,000 | 48.55bn |
| Other purpose | 195,592 | 12.2% | 47.8% | 95,000 | 17.45bn |
| Refinancing | 188,094 | 11.8% | 60.3% | 205,000 | 48.89bn |
| Not applicable | 238 | 0.0% | 64.3% | 215,000 | 0.09bn |

**Purpose tells you far more than type does.** The four loan types span 13.3 points, but the spread only looks wide because of RHS at 1,930 applications: conventional and FHA together are 97.7 percent of the market and sit 2.6 points apart. Purpose spans 24.4 points, from 72.2 percent on a home purchase to 47.8 percent on "other purpose".

And the money concentrates harder than the volume. Home purchase is 46 percent of applications and **65 percent of the dollars**. Home improvement is the mirror image: 15.5 percent of applications and 4.3 percent of the dollars, on a median loan of 85,000, with the second lowest approval rate in the table. A lender running a portfolio here is running two different businesses that happen to share a regulator.

---

## 4. Finding 3: a quarter of this market sits behind someone else's claim

Run live [▶ query 04](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=04)

```sql
-- General analysis section 3: where the loan sits in the capital stack.
-- A subordinate lien is repaid only after the first lien, which is why it is
-- approved less often for a much smaller amount.
SELECT c.label                                           AS lien_status,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code c ON c.code_field = 'lien_status' AND c.code_value = p.lien_status
WHERE f.action_taken <> '6'
GROUP BY 1 ORDER BY 2 DESC, 1;
```

Lien position is the single most informative structural field HMDA publishes. A first lien is repaid first if the property is sold or foreclosed. A subordinate lien is repaid only after the first lien is satisfied, which is why it is priced and underwritten differently.

| lien position | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Secured by a first lien | 1,178,483 | 73.8% | **65.7%** | 305,000 | 344.78bn |
| Secured by a subordinate lien | 418,193 | 26.2% | **53.1%** | 85,000 | 26.64bn |

Alongside it, from the same junk dimension:

| | applications | share | approval rate |
|---|---|---|---|
| Open-end line of credit | 402,611 | 25.2% | 53.0% |
| Business or commercial purpose | 130,382 | 8.2% | 62.9% |
| Nonconforming | 66,938 | 4.2% | 63.4% |
| Reverse mortgage | 4,767 | 0.3% | 68.6% |

**Second-lien and open-end lending is a quarter of this market and 7 percent of its money.** Approved 12.6 points less often, for a median loan less than a third the size. The overlap between the two rows is almost total: these are home equity lines, and they are what the home improvement purpose in section 3 is mostly made of.

**What is not here, and why.** HMDA also publishes `balloon_payment`, `interest_only_payment`, `negative_amortization`, `other_nonamortizing_features` and `prepayment_penalty_term`. Those are the structural features that matter most for credit risk, and they are the ones that defined 2008. They exist in `raw.raw_lar` in this project and were not carried into the model. That is a real gap, it is deliberate rather than accidental, and closing it means a migration, a fact table reload and a fresh Parquet export. It is the first thing I would add.

---

## 5. Finding 4: two thirds of applications are for exactly thirty years

Run live [▶ query 05](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=05)

```sql
-- General analysis section 4: how long the loans run.
-- 30 years and above is one band on purpose: terms beyond 360 months are rare
-- and behave like 30-year lending rather than like a separate product.
WITH d AS (
  SELECT CASE WHEN loan_term_months IS NULL      THEN '6 not reported'
              WHEN loan_term_months <= 120       THEN '1 up to 10 years'
              WHEN loan_term_months <= 180       THEN '2 10 to 15 years'
              WHEN loan_term_months <= 240       THEN '3 15 to 20 years'
              WHEN loan_term_months <  360       THEN '4 20 to under 30 years'
              ELSE                                    '5 30 years and above'
         END AS term_band, action_taken, loan_amount
  FROM marts.fct_application
  WHERE action_taken <> '6')
SELECT term_band,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM d GROUP BY 1 ORDER BY 1;
```

| term | applications | share | approved | approval rate | median approved | disbursed |
|---|---|---|---|---|---|---|
| Up to 10 years | 87,744 | 5.5% | 55,296 | 63.0% | 75,000 | 26.66bn |
| 10 to 15 years | 99,504 | 6.2% | 66,102 | 66.4% | 125,000 | 16.84bn |
| 15 to 20 years | 130,141 | 8.2% | 73,333 | **56.3%** | 105,000 | 11.02bn |
| 20 to under 30 years | 115,651 | 7.2% | 63,309 | **54.7%** | 115,000 | 11.00bn |
| **30 years and above** | **1,078,159** | **67.5%** | 684,349 | 63.5% | 315,000 | **290.13bn** |
| Not reported | 85,477 | 5.4% | 54,159 | 63.4% | 125,000 | 15.77bn |

1,062,501 applications are for exactly 360 months. Terms beyond 360 are rare and behave like 30-year lending, so they sit in the same band.

**The 30-year mortgage is 67.5 percent of applications and 78 percent of the money.** Everything else is a rounding error by value.

The interesting row is the one in the middle. The 15 to 30 year bands approve at 56.3 and 54.7 percent, the two worst in the table, and worse than both the shorter and the longer terms around them. That is not a term effect, it is a composition effect: those bands are where the second-lien and home improvement lending sits, and section 4 already showed what that does to an approval rate. Shorter terms are small secured loans that clear easily; 30 years is a first mortgage on a purchase. The middle is neither.

---

## 6. Finding 5: the average loan is not a loan anyone gets

Run live [▶ query 06](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=06)

```sql
-- General analysis section 5: loan size, approved loans only.
-- The mean sits far above the median in every year, which is the signature of
-- a right-skewed distribution: a few very large loans, most of them small.
SELECT activity_year,
       count(*)                                                       AS approved,
       round(CAST(percentile_cont(0.10) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p10,
       round(CAST(percentile_cont(0.25) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p25,
       round(CAST(percentile_cont(0.50) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS median,
       round(CAST(percentile_cont(0.75) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p75,
       round(CAST(percentile_cont(0.90) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p90,
       round(CAST(avg(loan_amount) AS numeric))                       AS mean
FROM marts.fct_application
WHERE action_taken IN ('1','2')
GROUP BY 1 ORDER BY 1;
```

Approved loans only.

| year | p10 | p25 | median | p75 | p90 | **mean** |
|---|---|---|---|---|---|---|
| 2022 | 65,000 | 125,000 | 255,000 | 485,000 | 785,000 | **417,647** |
| 2023 | 55,000 | 105,000 | 215,000 | 455,000 | 705,000 | **358,277** |
| 2024 | 55,000 | 105,000 | 235,000 | 475,000 | 735,000 | **368,593** |
| 2025 | 65,000 | 125,000 | 255,000 | 505,000 | 795,000 | **401,264** |

**The mean sits above the 60th percentile in every year.** In 2025 the average approved loan is 401,264 and the median is 255,000, a gap of 57 percent. That is the signature of a right-skewed distribution: a small number of very large loans pulling the average away from anything typical. Any headline quoting a mortgage "average" in this market is describing a loan most borrowers do not get, which is why every other table in this document uses the median.

The spread also widened faster than the middle moved. Between 2023 and 2025 the median rose 40,000 while the 90th percentile rose 90,000.

**One thing to know about these numbers.** There are only **923 distinct loan amounts** across 951,371 originated loans, and 99.8 percent are exact multiples of 5,000. The Bureau rounds loan amounts before publication to protect applicant privacy. Every median here will land on a round number, and a histogram of this column is spiky by construction. That is the data, not a bug, and it is why loan amount is never used here for anything finer than a percentile.

---

## 7. Finding 6: approval falls with every decade of age, and so does loan size

Run live [▶ query 07](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=07)

```sql
-- General analysis section 6: the applicant age funnel.
-- 8888 is HMDA's code for an age that was not provided. It is kept as its own
-- band rather than dropped, because it turns out not to be a demographic at all:
-- 84 percent of those originations are business or commercial purpose lending,
-- where the borrower is a company and has no age to report.
WITH d AS (
  SELECT CASE WHEN a.applicant_age = '8888'              THEN '7 Age not provided'
              WHEN a.applicant_age IN ('65-74','>74')    THEN '6 65 and above'
              WHEN a.applicant_age = '<25'               THEN '1 Under 25'
              WHEN a.applicant_age = '25-34'             THEN '2 25-34'
              WHEN a.applicant_age = '35-44'             THEN '3 35-44'
              WHEN a.applicant_age = '45-54'             THEN '4 45-54'
              WHEN a.applicant_age = '55-64'             THEN '5 55-64'
         END AS age_band, f.action_taken, f.loan_amount
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken <> '6')
SELECT age_band,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct_of_applications,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved_loan,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS total_disbursed_bn
FROM d GROUP BY 1 ORDER BY 1;
```

| age band | applications | % of applications | approved | approval rate | median approved loan | total disbursed |
|---|---|---|---|---|---|---|
| Under 25 | 35,382 | 2.2% | 24,327 | **68.8%** | 195,000 | 6.35bn |
| 25-34 | 299,818 | 18.8% | 206,168 | **68.8%** | 285,000 | 75.39bn |
| 35-44 | 396,860 | 24.9% | 254,134 | 64.0% | **295,000** | **103.03bn** |
| 45-54 | 338,638 | 21.2% | 204,910 | 60.5% | 225,000 | 70.79bn |
| 55-64 | 272,665 | 17.1% | 158,708 | 58.2% | 185,000 | 44.64bn |
| 65 and above | 195,509 | 12.2% | 109,652 | **56.1%** | 155,000 | 25.49bn |
| Age not provided | 57,804 | 3.6% | 38,649 | 66.9% | **565,000** | 45.71bn |

**Approval falls monotonically, 12.7 points from 25-34 down to 65 and above, and the median loan falls with it from 295,000 to 155,000.** Older applicants ask for less and hear no more often. Both movements are clean, neither reverses, and the 35-44 band alone writes 103bn, more than the two oldest bands combined.

**The not-provided row is not a demographic.** HMDA codes an unreported age as `8888`, and it would be easy to drop it. Checking it first pays off:

| | age not provided | every other band |
|---|---|---|
| Business or commercial purpose | **84.3%** | 5.1% |
| Multifamily property | **36.5%** | 0.1% |

These are companies. A limited partnership buying an apartment building has no applicant age to report, which is why the median approved loan is 565,000 against 155,000 to 295,000 everywhere else. Reported as its own band rather than excluded, because the alternative is silently removing 45.71bn of commercial lending from a market analysis.

---

## 8. Finding 7: a second name on the application is worth ten points

Applicant sex, as a funnel. Purchased loans are excluded, as everywhere in this
phase, because nobody applied for those.

Run live [▶ query 08](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=08)

```sql
SELECT a.derived_sex                                                 AS applicant_sex,
       count(*)                                                      AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
             / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1)      AS pct_of_applications,
       count(*) FILTER (WHERE f.action_taken IN ('1','2'))           AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 1)                   AS approval_rate,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                            AS median_approved,
       round(CAST(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                                        AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY 1 ORDER BY 2 DESC;
```

| applicant sex | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Male | 557,903 | 34.9% | 58.9% | 225,000 | 111.93bn |
| Joint | 505,023 | 31.6% | **69.5%** | 265,000 | 130.91bn |
| Female | 371,627 | 23.3% | 59.6% | 195,000 | 59.60bn |
| *Sex not available* | 162,123 | *10.2%* | *58.9%* | *335,000* | *68.97bn* |

**What this says.** Male and female applicants are approved at almost exactly the
same rate, 58.9 against 59.6 percent. The thing that moves the number is not
which sex applied but how many people applied. A jointly named application is
approved 10.6 points more often than a male applicant and 9.9 points more often
than a female one.

That is not surprising once stated plainly, and it is worth stating plainly: two
incomes and two credit records are a stronger application than one. It is the
clearest example in this phase of a gap that looks demographic and is really
structural.

Two rows deserve a caution. **Joint is not a sex.** HMDA assigns it when two
applicants of different sexes apply together, so it belongs in this table as its
own row but it is not comparable with the other three as a category of person.
And *sex not available* carries the highest median approved loan in the table at
335,000 dollars, well above every named category. That is the same signal as the
age funnel in section 7: these are disproportionately companies, trusts and
estates rather than people who declined to answer.

The equivalent cut by applicant race, and the two crossed together, are in
[phase 08b section 4.1](08b_analysis_disparity.md). They sit there rather than
here because a cut that crosses applicant race is part of the disparity
question, and this phase describes the market.

---

## 9. Finding 8: the biggest market has the lowest approval rate

Run live [▶ query 09](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=09)

```sql
-- General analysis section 7: where the lending happens.
-- msa_md 99999 is HMDA's code for a property outside any metropolitan area, so
-- it has no name in dim_msa and is labelled here rather than left blank.
-- NULLS LAST is not decoration: PostgreSQL sorts NULLs first on DESC and DuckDB
-- sorts them last, so without it the two engines return different top tens.
SELECT CASE WHEN coalesce(m.msa_md_name, '') = ''
            THEN 'Outside any metropolitan area' ELSE m.msa_md_name END AS area,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct_of_state,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(coalesce(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
LEFT JOIN marts.dim_msa m
       ON m.activity_year = f.activity_year AND m.msa_md = f.msa_md
WHERE f.action_taken <> '6'
GROUP BY 1
ORDER BY 2 DESC NULLS LAST, 1
LIMIT 10;
```

| area | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| New York-Jersey City-White Plains | 482,104 | 30.2% | **58.3%** | 495,000 | **184.86bn** |
| Nassau County-Suffolk County | 325,669 | 20.4% | 59.5% | 405,000 | 87.51bn |
| Outside any metropolitan area | 145,478 | 9.1% | 60.6% | 135,000 | 15.29bn |
| Rochester | 130,901 | 8.2% | **71.7%** | 135,000 | 15.06bn |
| Buffalo-Cheektowaga | 121,972 | 7.6% | 68.4% | 165,000 | 16.16bn |
| Albany-Schenectady-Troy | 113,855 | 7.1% | 65.9% | 185,000 | 15.62bn |
| Syracuse | 71,962 | 4.5% | 68.8% | 135,000 | 8.17bn |
| Poughkeepsie-Newburgh-Middletown | 45,897 | 2.9% | 61.8% | 255,000 | 7.64bn |
| Kiryas Joel-Poughkeepsie-Newburgh | 40,485 | 2.5% | 63.4% | 265,000 | 7.32bn |
| Utica-Rome | 30,141 | 1.9% | 68.2% | 125,000 | 2.89bn |

**New York City is 30 percent of the state's applications, 50 percent of its lending by value, and the lowest approval rate in the table.** The two downstate markets together are half the applications and 73 percent of the money.

The ranking by volume and the ranking by dollars are genuinely different lists. Rochester is fourth by applications and sixth by dollars. Buffalo is fifth by applications and third by dollars. A capacity plan built on application counts and a balance sheet built on exposure would point at different offices.

Upstate approves far more readily, 71.7 percent in Rochester against 58.3 in New York City, on a median loan less than a third the size. That is mostly price: the same borrower profile is a much larger loan-to-income multiple in a 495,000 market than in a 135,000 one.

**A portability bug found while building this table.** PostgreSQL sorts NULLs *first* on `ORDER BY ... DESC`; DuckDB sorts them *last*. Three MSAs with one or two applications and no dollars floated to the top of the by-dollars list in Postgres and not in DuckDB. No error in either engine, just a different top ten. The query now says `NULLS LAST` explicitly. Phase 10 has the full list of these.

---

## 9.1 Finding 8b: where the expensive property is

Section 9 ranks places by how much lending happens. This ranks them by how much
the houses cost, which is a different question and gives a different list.

Run live [▶ query 09b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=09b)

```sql
SELECT f.census_tract,
       max(m.msa_md_name)                                           AS metro_area,
       count(*)                                                     AS loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS numeric))                                           AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS numeric))                                           AS median_loan,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands)
             AS numeric))                                           AS median_income_k
FROM marts.fct_application f
LEFT JOIN marts.dim_msa m
  ON m.activity_year = f.activity_year AND m.msa_md = f.msa_md
WHERE f.action_taken = '1'
  AND f.property_value IS NOT NULL
  AND f.census_tract <> 'UNKNOWN'
GROUP BY 1
HAVING count(*) >= 100
ORDER BY 4 DESC, 1
LIMIT 10;
```

| census tract | metro area | loans | median property value | median loan | median income |
|---|---|---|---|---|---|
| 36103190712 | Nassau County-Suffolk County | 297 | 6,415,000 | 2,435,000 | 1,160,000 |
| 36103200901 | Nassau County-Suffolk County | 240 | 6,105,000 | 2,355,000 | 1,150,000 |
| 36103190801 | Nassau County-Suffolk County | 275 | 5,405,000 | 2,085,000 | 1,050,000 |
| 36061013000 | New York-Jersey City-White Plains | 192 | 5,005,000 | 1,785,000 | 1,108,000 |
| 36061004700 | New York-Jersey City-White Plains | 114 | 4,995,000 | 2,535,000 | 1,000,000 |
| 36061003900 | New York-Jersey City-White Plains | 379 | 4,205,000 | 2,205,000 | 877,000 |
| 36061009901 | New York-Jersey City-White Plains | 254 | 4,075,000 | 2,005,000 | 839,000 |
| 36103201006 | Nassau County-Suffolk County | 285 | 4,005,000 | 1,505,000 | 805,000 |
| 36061003300 | New York-Jersey City-White Plains | 348 | 3,855,000 | 2,045,000 | 830,000 |
| 36061004900 | New York-Jersey City-White Plains | 197 | 3,705,000 | 1,755,000 | 645,000 |

**What this says.** Every tract in the top ten is in one of two places. The 36103
tracts are Suffolk County, which is the eastern end of Long Island, and the
36061 tracts are Manhattan. In the most expensive of them the typical house
bought with a mortgage cost 6.4 million dollars and the typical buyer reported an
income of 1.16 million.

Property value is used rather than loan amount, and the distinction matters. A
large loan in a cheap area and a small loan in an expensive one look identical
on loan size alone. Property value answers the question actually being asked.

The threshold of 100 originated loans is what keeps this honest. Without it the
list would be whichever tract happened to sell one mansion, and the ranking
would measure luck rather than the neighbourhood.

## 10. Finding 9: income sets the size of the loan, not the multiple

Run live [▶ query 10](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=10)

```sql
-- General analysis section 8: income against loan size.
-- Two questions in one result: the level (what does a typical applicant at this
-- income borrow) and the spread (how wide is the range within one income band).
WITH d AS (
  SELECT CASE WHEN income_thousands IS NULL THEN '6 not reported'
              WHEN income_thousands <  50   THEN '1 under 50k'
              WHEN income_thousands < 100   THEN '2 50-100k'
              WHEN income_thousands < 150   THEN '3 100-150k'
              WHEN income_thousands < 200   THEN '4 150-200k'
              ELSE                               '5 200k and above'
         END AS income_band, action_taken, loan_amount
  FROM marts.fct_application
  WHERE action_taken <> '6')
SELECT income_band,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.25) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS p25_approved,
       round(CAST(percentile_cont(0.50) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(percentile_cont(0.75) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS p75_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM d GROUP BY 1 ORDER BY 1;
```

| income band | applications | share | approval rate | p25 | median | p75 | disbursed |
|---|---|---|---|---|---|---|---|
| under 50k | 160,387 | 10.0% | **46.0%** | 65,000 | 105,000 | 165,000 | 11.76bn |
| 50-100k | 428,470 | 26.8% | 60.5% | 85,000 | 155,000 | 235,000 | 43.11bn |
| 100-150k | 349,698 | 21.9% | 65.1% | 115,000 | 245,000 | 405,000 | 60.48bn |
| 150-200k | 204,876 | 12.8% | **67.1%** | 155,000 | 325,000 | 525,000 | 47.04bn |
| 200k and above | 339,585 | 21.3% | 66.2% | 255,000 | 505,000 | 815,000 | **145.76bn** |
| not reported | 113,660 | 7.1% | 64.9% | 215,000 | 465,000 | 905,000 | 63.27bn |

And the same approved loans expressed as a multiple of income:

| income band | p25 | median | p75 |
|---|---|---|---|
| under 50k | 1.56 | **2.62** | 3.71 |
| 50-100k | 1.15 | 2.16 | 3.15 |
| 100-150k | 0.96 | 2.03 | 3.35 |
| 150-200k | 0.87 | 1.92 | 3.08 |
| 200k and above | 0.73 | **1.53** | 2.46 |

**The level rises with income and the multiple falls.** An applicant under 50,000 borrows 2.62 times their income; one over 200,000 borrows 1.53 times. Higher earners take proportionally less leverage, which is the opposite of what a naive reading of the first table suggests.

The spread widens enormously alongside it. The middle half of the bottom band is 65,000 to 165,000, a 100,000 window. The middle half of the top band is 255,000 to 815,000, a 560,000 window. Income predicts loan size well at the bottom and poorly at the top, where property choice and equity matter more than salary.

**Approval stops improving after 150k.** It climbs 21 points from the bottom band to 150-200k, then falls back slightly. Money buys approval up to a point and then stops buying it, which makes the top band a useful control in phase 08b: if a gap survives at 200,000 of income, income is not what is producing it.

---

## 11. Finding 10: the rate environment swamps the product

Run live [▶ query 11](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=11)

```sql
-- General analysis section 9: what borrowing costs.
-- Restricted to 2025 and to originated loans. Both restrictions are load
-- bearing. A rate exists only on a loan that was actually made, and the median
-- rate moved from 4.375 percent in 2022 to 6.875 in 2024, so pooling the four
-- years would measure the rate environment rather than the product.
SELECT c.label                                           AS loan_purpose,
       count(*)                                          AS loans,
       round(CAST(avg(f.interest_rate) AS numeric), 3)    AS mean_rate,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS numeric), 3)                             AS median_rate
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code c ON c.code_field = 'loan_purpose' AND c.code_value = p.loan_purpose
WHERE f.action_taken = '1'
  AND f.interest_rate IS NOT NULL
  AND f.activity_year = 2025
GROUP BY 1 ORDER BY 4, 1;
```

Originated loans only, because a rate exists only on a loan that was actually made. Coverage is **96.4 percent** of originations, stable across all four years, and the missing 3.6 percent is concentrated in exempt filers rather than spread evenly.

| year | loans | median rate |
|---|---|---|
| 2022 | 295,588 | **4.375%** |
| 2023 | 195,869 | 6.750% |
| 2024 | 201,572 | **6.875%** |
| 2025 | 224,073 | 6.625% |

**A 250 basis point move in twelve months.** Nothing else in this document comes close, and it is why every cut below is computed within a single year. Pooling four years would measure which products were popular in 2022, not how products are priced.

2025 only:

| loan purpose | loans | mean rate | median rate |
|---|---|---|---|
| Refinancing | 25,772 | 6.585% | **6.490%** |
| Home purchase | 115,778 | 6.594% | 6.500% |
| Home improvement | 29,853 | 6.883% | 6.940% |
| Cash-out refinancing | 29,913 | 7.284% | 6.990% |
| Other purpose | 22,728 | 7.057% | **7.000%** |

| loan type, 2025 | median rate | | income band, 2025 | median rate |
|---|---|---|---|---|
| VA | **6.250%** | | under 50k | **6.875%** |
| FHA | 6.375% | | 50-100k | 6.550% |
| RHS or FSA | 6.375% | | 100-150k | 6.575% |
| Conventional | 6.625% | | 150-200k | 6.625% |
| | | | 200k and above | **6.500%** |

Three things fall out of this. **Government guaranteed paper is cheaper**, 37.5 basis points between VA and conventional, which is what the guarantee is for. **Purpose matters more than type**, a 51 basis point spread against 37.5. And **the lowest income band pays 37.5 basis points more than the highest**, which is the same size as the entire VA discount.

Cash-out refinancing is the row worth a second look: its median is 6.990 but its mean is 7.284, the largest mean-to-median gap in the table. Something in that product has a long right tail that the others do not.

---

## 12. Finding 11: more than a third of denials are one reason

Run live [▶ query 12](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=12)

```sql
-- General analysis section 10: why applications fail.
-- Uses marts.v_denial_reason, the labelled view, restricted to reason_ordinal 1
-- so each denial is counted once under its primary reason. Restricted to
-- genuinely denied applications because 21,665 originated loans also carry a
-- denial reason, which is a filer error in the published data.
--
-- coalesce is not cosmetic. 31,821 denial-reason rows carry code 1111, HMDA's
-- "Exempt" value, and ref_code has no mapping for it, so the labelled view
-- returns NULL. Blanking it would hide 4,533 primary reasons. The gap belongs
-- in the ref_code seed; until it is fixed the code is named here.
SELECT coalesce(v.denial_reason, 'Exempt (code 1111, unmapped)') AS primary_reason,
       count(*)                                          AS denials,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct
FROM marts.v_denial_reason v
JOIN marts.fct_application f
  ON f.activity_year = v.activity_year AND f.application_sk = v.application_sk
WHERE v.reason_ordinal = 1 AND f.action_taken = '3'
GROUP BY 1 ORDER BY 2 DESC, 1;
```

HMDA lets a filer record up to four denial reasons. This project keeps them in a bridge table, `marts.br_denial_reason`, because flattening four optional reasons into four columns on the fact table would break first normal form. 78.3 percent of denials give one reason, 17.9 percent give two, 3.4 percent three and 0.5 percent all four.

Primary reason, on genuinely denied applications:

| primary reason | denials | share |
|---|---|---|
| **Debt-to-income ratio** | 117,389 | **36.7%** |
| Credit history | 74,093 | 23.2% |
| Collateral | 53,373 | 16.7% |
| Other | 30,692 | 9.6% |
| Credit application incomplete | 21,413 | 6.7% |
| Unverifiable information | 9,205 | 2.9% |
| Insufficient cash (downpayment, closing costs) | 5,657 | 1.8% |
| *Exempt (code 1111, unmapped)* | 4,533 | 1.4% |
| Employment history | 3,037 | 1.0% |
| Mortgage insurance denied | 81 | 0.0% |

**Debt-to-income is the single largest reason at 36.7 percent, and on its own it is almost as large as credit history and collateral together at 39.9.** That is worth sitting with, because it reframes the affordability question: the binding constraint in this market is more often what the applicant already owes than what they have previously repaid badly.

Two data problems are visible in this table rather than hidden.

**21,665 originated loans carry a denial reason.** The loan was made, and a reason for refusing it was filed alongside. That is a filer error, it is in the published data, and it is why this query restricts to `action_taken = '3'` instead of trusting the bridge alone. Phase 07's assertion framework should be catching this and is not.

**Code 1111 has no label.** 31,821 denial-reason rows carry HMDA's "Exempt" value and `ref.ref_code` has no mapping for it, so the labelled view returns NULL. Blanking those rows would have quietly removed 4,533 primary reasons from this table, so the code is named instead. This is the same class of gap as the `applicant_credit_score_type` one documented in phase 07 section 5, and it belongs in the `ref_code` seed.

---

## 13. What this analysis cannot say

**There is no credit score in HMDA.** The regulator does not collect it. It is the strongest legitimate predictor of a credit decision and it is absent from every number above. Nothing here is causal.

**Race is unreported for 18.7 percent of applications and sex for 10.2 percent.** Age is unreported for 3.6 percent, and section 7 shows that band is mostly companies rather than reticent people. The direction of the bias in the other two is unknown.

**Income is self-reported and rounded.** So are loan amounts, to the nearest 5,000. Loan-to-income multiples inherit both roundings.

**Vintages are mixed.** 2022 is a Three Year file, 2023 and 2024 are One Year files, 2025 is provisional. Some of the 2022 to 2023 fall is filing completeness rather than market movement. Phase 01 section 4 has the detail, and phase 08b section 3 shows what survives once that is accounted for.

---

## 14. The SQL this phase actually exercises

| technique | where it earns its place |
|---|---|
| `FILTER (WHERE ...)` aggregates | every rate and every conditional median here, in one pass instead of self-joins |
| `percentile_cont` ordered-set aggregates | medians and quartiles throughout, and the whole of section 6 |
| `percentile_cont` over a `CASE` | median of approved loans computed in the same pass as the count of all applications |
| `LATERAL (VALUES ...)` | unpivots the one-row KPI aggregate in section 0 into a readable metric and value list |
| Windows over aggregates | share and running share of market in section 2.1, computed across all 1,168 lenders while returning ten rows |
| Window functions | share-of-total columns without a second scan |
| Junk dimension joins | loan type, purpose, lien status and structure all come from one 194-row table |
| Bridge-table joins | section 12, because denial reasons are one-to-many |
| Generated views | `sync_views.py` writes `bootstrap.sql` from `pg_get_viewdef` so the browser build cannot drift from the database |
| Exact decimal arithmetic | `DECIMAL(24,8)` rather than float, because four of these queries returned different answers in the two engines until it was fixed |

---

## 15. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| Excluding purchased loans from the funnel | counting every row as an application | nobody applied; including them made one age band read 19.9% instead of 66.9% |
| Approved = originated plus approved-not-accepted | originated only | the lender said yes in both cases; disbursed is reported separately for the money question |
| Median everywhere, mean only alongside it | the mean | the mean approved loan sits above the 60th percentile in every year |
| Keeping the not-provided bands in the table | filtering them out | the age one turned out to be 84% commercial lending, which is a finding, not noise |
| Interest rate cuts within a single year | pooling four years | the median rate moved 250 basis points between 2022 and 2024 |
| Reporting the 21,665 contradictory denial reasons | dropping them silently | it is a defect in the published data and the assertion suite should catch it |
| Naming unmapped code 1111 | letting it render blank | blanking it would have removed 4,533 denials from the table |
| `DECIMAL(24,8)` rather than float division | `/1e9` and `AS numeric` | the two engines disagreed in the second decimal place, and the parity test caught it |
| `NULLS LAST` written explicitly | relying on the default | the two engines have opposite defaults and neither raises an error |
