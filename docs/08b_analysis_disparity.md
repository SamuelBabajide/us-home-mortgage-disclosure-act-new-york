# Phase 08b: The disparity analysis

Do outcomes differ by applicant group, and does the difference survive holding income, product, neighbourhood and lender constant?

This is the second of two analysis documents. [Phase 08](08_analysis.md) describes the market itself: what was borrowed, by whom, where, how much and at what price. This one asks a narrower question of the same data, and it is deliberately separate, because a document that answers both at once answers neither well.

Every table links to the browser playground, which opens with that query loaded and already executed. Section 12 states in full what this analysis cannot say, and it is worth reading before the findings rather than after.

---

## 1. The denominator decision, which comes before every number

Run live [▶ query 14](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=14)

```sql
SELECT f.action_taken, c.label,
       count(*)                                              AS rows,
       round(100.0*count(*)/sum(count(*)) OVER (), 1)         AS pct
FROM marts.fct_application f
JOIN ref.ref_code c ON c.code_field='action_taken' AND c.code_value=f.action_taken
GROUP BY 1,2
ORDER BY 3 DESC;
```

HMDA records eight possible outcomes for an application, and only two of them are a lender's credit decision:

| code | outcome | rows | share of all 1,754,846 |
|---|---|---|---|
| 1 | Loan originated | 951,371 | 54.2% |
| 3 | Application denied | 319,473 | 18.2% |
| 4 | Withdrawn by applicant | 193,863 | 11.0% |
| 6 | Purchased loan | 158,170 | 9.0% |
| 5 | File closed for incompleteness | 78,521 | 4.5% |
| 2 | Approved but not accepted | 45,177 | 2.6% |
| 8 | Preapproval approved, not accepted | 6,982 | 0.4% |
| 7 | Preapproval request denied | 1,289 | 0.1% |

**What this says.** Only rows 1 and 3 are a lender saying yes or no. A purchased loan is one another lender already approved. A withdrawal is the applicant walking away. Counting those as approvals or denials measures something other than lending decisions.

A denial rate is therefore `denied / (originated + denied)`, and nothing else. Measured over all 1,754,846 rows the denied share is 18.2 percent. Measured correctly, over decided applications only, it is 25.1 percent. Those are the same data and a 7 point difference, because a purchased loan is a loan someone else already approved and a withdrawal is the applicant's decision rather than the lender's.

This is why the model puts the definition in one place rather than in every query:

```sql
(f.action_taken IN ('1','3')) AS is_decided,
(f.action_taken = '3')        AS is_denied
```

Every figure below uses `is_decided` as the denominator. Getting this wrong is the single most common way to publish a wrong fair-lending number, and the reason phase 05 built a partial index on exactly this predicate.

---

## 2. Finding 1: the market tightened, then partly recovered

Run live [▶ query 13](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=13)

```sql
SELECT activity_year,
       count(*)                                                        AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3')/count(*),2) AS denial_pct
FROM marts.fct_application
WHERE action_taken IN ('1','3')
GROUP BY 1
ORDER BY 1;
```

| year | decided applications | denial rate |
|---|---|---|
| 2022 | 400,563 | 23.29% |
| 2023 | 277,970 | 26.94% |
| 2024 | 283,192 | 26.26% |
| 2025 | 309,119 | 24.87% |

**What this says.** When interest rates rose in 2023, a third fewer people got a decision at all, and the ones who did were turned down more often. Both numbers moved against the borrower at the same time.

Decided volume falls by 31 percent from 2022 to 2023 as rates rise, and the denial rate moves 3.65 points the other way. 2025 is the provisional vintage, so it is shown but not used for any trend claim. Phase 01 section 4 explains why.

---

## 3. Finding 2: what caused the 2023 deterioration, and where I was wrong

**I predicted this incorrectly before measuring it, and the correction is more instructive than the result.**

My reasoning was that the 2023 collapse in refinancing would push the aggregate denial rate *down*, because refinancing carries a higher denial rate than home purchase and there was suddenly much less of it. That is sound as far as it goes, and it is wrong, because it only considered the mix and ignored what happened inside each product.

A shift-share decomposition separates the two. The change in an aggregate rate is the sum of a **mix effect** (the same products, in different proportions) and a **within effect** (the same proportions, at different rates).

Run live [▶ query 17](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=17)

```sql
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
        max(CASE WHEN yr=2022 THEN 1.0*y.decided/t.tot   END) AS w22,
        max(CASE WHEN yr=2023 THEN 1.0*y.decided/t.tot   END) AS w23,
        max(CASE WHEN yr=2022 THEN 1.0*y.denied/y.decided END) AS r22,
        max(CASE WHEN yr=2023 THEN 1.0*y.denied/y.decided END) AS r23
      FROM y JOIN t USING (yr) GROUP BY 1)
SELECT round(100*sum((w23-w22)*r22), 3) AS mix_effect,
       round(100*sum(w23*(r23-r22)), 3) AS within_effect,
       round(100*(sum((w23-w22)*r22) + sum(w23*(r23-r22))), 3) AS total_change
FROM j;
```

| effect | points | share of the change |
|---|---|---|
| mix, products changing weight | +0.860 | 23.6% |
| within, products denying more | +2.790 | **76.4%** |
| total | +3.650 | matches 23.29 to 26.94 |

**What this says.** Roughly a quarter of the 2023 rise came from the market shifting towards products that were always harder to get. The other three quarters came from products getting harder to get. The second is much the bigger story, and it is the one I had missed.

So the answer is the opposite of my prediction. Refinancing shrinking did push the rate down, by 1.09 points for refinancing and 1.38 for cash-out. But home improvement and "other purpose" grew from 25.0 to 32.1 percent of the market combined, and both deny at over 40 percent, which more than cancelled it out. And underneath all of that, **every single product denied more often in 2023 than in 2022.**

Run live [▶ query 17b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=17b)

```sql
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
```

| purpose | share 2022 | share 2023 | rate 2022 | rate 2023 | mix | within |
|---|---|---|---|---|---|---|
| Home improvement | 14.9% | 18.2% | 40.9% | 44.5% | +1.361 | +0.657 |
| Other purpose | 10.1% | 13.9% | 41.8% | 46.3% | +1.579 | +0.628 |
| Refinancing | 13.8% | 9.1% | 23.1% | 28.9% | -1.087 | +0.528 |
| Home purchase | 44.8% | 47.9% | 12.6% | 13.7% | +0.390 | +0.502 |
| Cash-out refinancing | 16.4% | 10.9% | 25.2% | 29.5% | -1.383 | +0.469 |
| *Not applicable* | *0.0%* | *0.0%* | *2.5%* | *25.8%* | *0.000* | *+0.005* |

**What this says.** Read the last two columns. A positive mix number means the market moved towards that product; a positive within number means that product itself got stricter. Refinancing and cash-out have negative mix numbers because they shrank, which pulled the market rate down. Every single within number is positive. The two columns sum to the +0.860 and +2.790 in the table above, which is how the detail and the summary are checked against each other. *Not applicable* is kept rather than dropped, at 174 decided applications, because without it the rows would not add up.

The lesson is the one worth keeping: an aggregate can move for two completely different reasons, and a plausible story about one of them is not an answer. The decomposition is four lines of arithmetic and it is the difference between being confidently wrong and being right.

---

## 4. Finding 3: outcomes differ sharply by applicant group

Run live [▶ query 15](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=15)

```sql
SELECT a.derived_race,
       count(*)                                                        AS decided,
       round(100.0*count(*) FILTER (WHERE f.action_taken='3')/count(*),1) AS denial_pct
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
GROUP BY 1
ORDER BY 2 DESC;
```

| group (2025) | decided | denial rate |
|---|---|---|
| Joint | 5,410 | 18.3% |
| White | 197,892 | 22.4% |
| Asian | 27,956 | 24.5% |
| *Race not available* | 52,526 | *27.8%* |
| **Black or African American** | 22,523 | **39.6%** |
| 2 or more minority races | 841 | 44.4% |
| American Indian or Alaska Native | 1,308 | 45.0% |
| Native Hawaiian or Other Pacific Islander | 583 | 49.9% |
| *Free form text only* | 80 | *62.5%* |

**What this says.** Among applicants who got a decision in 2025, a bit over one in five White applicants was turned down, and two in five Black applicants. Four groups were turned down more often than White applicants and one less often. Everything after this section is about testing whether other differences between applicants account for that.

Collapsing that to the comparison a reader will ask for, White against every other reported race combined:

Run live [▶ query 15b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=15b)

```sql
WITH d AS (
  SELECT f.action_taken,
         CASE WHEN a.derived_race = 'White' THEN 'White'
              WHEN a.derived_race IN ('Race Not Available','Free Form Text Only')
                   THEN 'Race not reported'
              ELSE 'All other reported races' END AS grp
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025)
SELECT grp AS applicant_group, count(*) AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken = '3')/count(*), 1) AS denial_pct
FROM d GROUP BY 1 ORDER BY 3;
```

| group (2025) | decided | denial rate |
|---|---|---|
| White | 197,892 | 22.4% |
| *Race not reported* | 52,606 | *27.9%* |
| **All other reported races combined** | 58,621 | **30.7%** |

**An 8.3 point gap, a ratio of 1.37.** "All other reported races" means every `derived_race` except White, excluding the two values that carry no race information, *Race Not Available* and *Free Form Text Only*. That exclusion matters: those two cover a quarter of all applications, and putting them on either side of the comparison would make the result an artefact of who declined to answer.

This is the conservative version of the comparison. The combined group includes Joint applicants, where one applicant is White, and they are denied *less* often than White applicants alone. Take Joint out and the other group rises to 32.0 percent, a 9.6 point gap.

It is also the least informative version, because it averages across groups that are very far apart. Asian applicants at 24.5 percent and Native Hawaiian or Other Pacific Islander applicants at 49.9 percent sit inside the same 30.7 percent. Both views are carried through the rest of this phase for that reason, and where they disagree the disagreement is reported rather than resolved.

Either way, the number on its own is close to meaningless, because applicants differ in income, in what they are borrowing for, in where the property is and in which lender they approached. The rest of this phase is about removing those explanations one at a time.


### 4.1 The same funnel, crossed with applicant sex

This section and the two tables in it were in the general analysis until they
were moved here. That phase describes the market; any cut that crosses applicant
race belongs to the disparity question, which is this one.

Read the denominators carefully, because they are not the ones used above.
Section 4 reports the **denial rate among decided applications in 2025**. The
tables here report the **approval rate across all four years, over every
application except purchased loans**. Both are defensible and they are not
comparable with each other. The first isolates a lender's yes or no in the
latest year; the second describes the whole four-year funnel, withdrawals and
incomplete files included.

| applicant race | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| White | 983,251 | 61.6% | 66.0% | 205,000 | 198.23bn |
| Race not available | 299,190 | 18.7% | 56.9% | 315,000 | 98.89bn |
| Asian | 147,339 | 9.2% | 62.1% | **455,000** | 44.13bn |
| Black or African American | 124,980 | 7.8% | 49.5% | 255,000 | 19.63bn |
| Joint | 27,293 | 1.7% | 68.0% | 355,000 | 8.86bn |
| American Indian or Alaska Native | 6,829 | 0.4% | 41.9% | 165,000 | 0.67bn |

Crossing the two gives the pivot.

Run live [▶ query 15c](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=15c)

```sql
SELECT a.derived_sex, a.derived_race,
       count(*)                                          AS applications,
       count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(coalesce(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
  AND a.derived_sex  IN ('Male','Female','Joint')
  AND a.derived_race IN ('White','Black or African American','Asian','Joint')
GROUP BY 1,2 ORDER BY 1, 3 DESC, 2;
```

<table>
<thead>
<tr><th rowspan="2">applicant sex</th><th rowspan="2">race</th><th colspan="2">volume</th><th colspan="3">outcome</th></tr>
<tr><th>applications</th><th>approved</th><th>approval rate</th><th>median approved</th><th>disbursed</th></tr>
</thead>
<tbody>
<tr><td rowspan="4">Joint</td><td>White</td><td align="right">365,685</td><td align="right">263,755</td><td align="right"><b>72.1%</b></td><td align="right">235,000</td><td align="right">89.01bn</td></tr>
<tr><td>Joint</td><td align="right">24,671</td><td align="right">16,849</td><td align="right">68.3%</td><td align="right">345,000</td><td align="right">8.05bn</td></tr>
<tr><td>Asian</td><td align="right">41,291</td><td align="right">26,624</td><td align="right">64.5%</td><td align="right">515,000</td><td align="right">14.83bn</td></tr>
<tr><td>Black or African American</td><td align="right">26,190</td><td align="right">14,828</td><td align="right">56.6%</td><td align="right">425,000</td><td align="right">6.02bn</td></tr>
<tr><td rowspan="4">Female</td><td>Asian</td><td align="right">41,146</td><td align="right">26,329</td><td align="right">64.0%</td><td align="right">405,000</td><td align="right">11.29bn</td></tr>
<tr><td>White</td><td align="right">234,089</td><td align="right">147,402</td><td align="right">63.0%</td><td align="right">165,000</td><td align="right">34.15bn</td></tr>
<tr><td>Joint</td><td align="right">999</td><td align="right">651</td><td align="right">65.2%</td><td align="right">335,000</td><td align="right">0.26bn</td></tr>
<tr><td>Black or African American</td><td align="right">52,701</td><td align="right">25,886</td><td align="right">49.1%</td><td align="right">225,000</td><td align="right">7.43bn</td></tr>
<tr><td rowspan="4">Male</td><td>White</td><td align="right">377,850</td><td align="right">234,748</td><td align="right">62.1%</td><td align="right">205,000</td><td align="right">74.22bn</td></tr>
<tr><td>Joint</td><td align="right">1,530</td><td align="right">996</td><td align="right">65.1%</td><td align="right">455,000</td><td align="right">0.53bn</td></tr>
<tr><td>Asian</td><td align="right">64,088</td><td align="right">38,093</td><td align="right">59.4%</td><td align="right">435,000</td><td align="right">17.83bn</td></tr>
<tr><td>Black or African American</td><td align="right">45,136</td><td align="right">20,875</td><td align="right"><b>46.2%</b></td><td align="right">215,000</td><td align="right">6.09bn</td></tr>
</tbody>
</table>

**The range across this table is 25.9 points, from 72.1 percent to 46.2
percent.** Two patterns run through it and they are independent of each other. A
jointly named application is approved roughly 8 points more often than a single
applicant of the same race, in every race group. And within each sex, the
ordering of race is identical.

**What this says.** Having two names on the application helps everyone by about
the same amount, and it does not close the distance between groups. The sex
effect and the group effect sit on top of one another rather than explaining one
another.

Product choice differs sharply too, and it is the mechanism behind a good deal of
what follows:

| group | conventional | FHA | VA | home purchase | subordinate lien |
|---|---|---|---|---|---|
| Black or African American | 78.3% | **18.6%** | 3.0% | 40.4% | 29.2% |
| American Indian or Alaska Native | 87.1% | 8.9% | 3.7% | 37.2% | 34.5% |
| White | 90.4% | 7.1% | 2.4% | 43.0% | 28.8% |
| Asian | **96.0%** | 3.5% | 0.5% | **67.6%** | 15.8% |

Black applicants use FHA at five times the Asian rate. Asian applicants are on a
home purchase two thirds of the time against Black applicants two fifths. Those
are different products with different approval rates and different prices, which
is exactly why section 6 tests whether the gap survives holding the product
constant.

---

## 5. Finding 4: the gap survives income

Banding income and pivoting the bands into columns keeps every group on one line. One pass, no self-joins, using `FILTER` twice per cell:

Run live [▶ query 16](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=16)

```sql
WITH d AS (
  SELECT f.action_taken, a.derived_race,
         CASE WHEN f.income_thousands <  50 THEN 'under 50k'
              WHEN f.income_thousands < 100 THEN '50k to 100k'
              WHEN f.income_thousands < 150 THEN '100k to 150k'
              WHEN f.income_thousands < 200 THEN '150k to 200k'
              ELSE                               '200k and above' END AS band
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
    AND f.income_thousands IS NOT NULL
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only'))
SELECT derived_race AS applicant_group, count(*) AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='under 50k')
             /nullif(count(*) FILTER (WHERE band='under 50k'),0), 1)      AS under_50k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='50k to 100k')
             /nullif(count(*) FILTER (WHERE band='50k to 100k'),0), 1)    AS b50_100k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='100k to 150k')
             /nullif(count(*) FILTER (WHERE band='100k to 150k'),0), 1)   AS b100_150k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='150k to 200k')
             /nullif(count(*) FILTER (WHERE band='150k to 200k'),0), 1)   AS b150_200k,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND band='200k and above')
             /nullif(count(*) FILTER (WHERE band='200k and above'),0), 1) AS over_200k
FROM d GROUP BY 1 ORDER BY 2 DESC;
```

Denial rate by applicant income, 2025:

| group | decided | under 50k | 50 to 100k | 100 to 150k | 150 to 200k | 200k and above |
|---|---|---|---|---|---|---|
| White | 191,212 | 45.3% | 25.6% | 19.2% | 16.2% | **15.7%** |
| Asian | 25,309 | 48.9% | 35.3% | 24.5% | 19.8% | 17.7% |
| Black or African American | 21,472 | 59.2% | 44.9% | 35.6% | 29.8% | **30.2%** |
| Joint | 5,255 | 50.0% | 30.4% | 19.3% | 15.8% | 13.2% |
| American Indian or Alaska Native | 1,260 | 65.8% | 43.6% | 41.5% | 43.1% | 30.9% |
| 2 or more minority races | 807 | 73.8% | 46.1% | 35.8% | 35.6% | 29.6% |
| Native Hawaiian or Other Pacific Islander | 564 | 68.4% | 55.3% | 45.4% | 38.5% | 36.2% |

**What this says.** Read along any row and denial falls as income rises, which is what anyone would expect. Now read down any column, which compares applicants earning roughly the same amount. The groups do not converge. In the highest band, where everyone earns over 200,000 dollars, White applicants are refused 15.7 percent of the time and Black applicants 30.2 percent.

Swap the `derived_race` grouping for the White against all other reported races split from section 4 and the same five bands give:

Run live [▶ query 16b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=16b)

```sql
WITH d AS (
  SELECT f.action_taken, f.income_thousands,
         CASE WHEN a.derived_race = 'White' THEN 'W' ELSE 'O' END AS grp,
         CASE WHEN f.income_thousands <  50 THEN 'under 50k'
              WHEN f.income_thousands < 100 THEN '50k to 100k'
              WHEN f.income_thousands < 150 THEN '100k to 150k'
              WHEN f.income_thousands < 200 THEN '150k to 200k'
              ELSE                               '200k and above' END AS band
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
    AND f.income_thousands IS NOT NULL
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only'))
SELECT applicant_income, white_decided, other_decided,
       white, all_other_reported_races,
       round(all_other_reported_races - white, 1) AS gap
FROM (
  SELECT band                              AS applicant_income,
         min(income_thousands)              AS band_floor,
         count(*) FILTER (WHERE grp='W')    AS white_decided,
         count(*) FILTER (WHERE grp='O')    AS other_decided,
         round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='W')
               /nullif(count(*) FILTER (WHERE grp='W'),0), 1) AS white,
         round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='O')
               /nullif(count(*) FILTER (WHERE grp='O'),0), 1) AS all_other_reported_races
  FROM d GROUP BY 1) s
ORDER BY band_floor;
```

| applicant income (2025) | White | all other reported races | gap |
|---|---|---|---|
| under 50k | 45.3% | 55.8% | 10.5 |
| 50k to 100k | 25.6% | 40.7% | 15.1 |
| 100k to 150k | 19.2% | 29.5% | 10.3 |
| 150k to 200k | 16.2% | 23.7% | 7.5 |
| 200k and above | 15.7% | 20.2% | 4.5 |

**What this says.** The gap column is simply the second column minus the first, so a reader can check it by subtraction. It never reaches zero. Among applicants earning over 200,000 dollars it is still 4.5 points.

Income explains a great deal about denial in general. The White rate falls from 45.3 percent in the bottom band to 15.7 percent in the top, and every group in the table falls with it.

It explains much less about the differences between groups. **Against all other reported races combined the gap is 10.5 points at the bottom, 15.1 points in the 50 to 100k band, and still 4.5 points among applicants earning over 200,000 dollars.** In ratio terms the combined other group is denied 1.2 to 1.6 times as often as White applicants in every band. Income does not close the gap at any level of income.

The combined figure does, however, understate what happens at the far end of the table, and this is the first place in the phase where the two views disagree. The Black gap against White is 13.6 to 19.3 points in every band and does not narrow at the top, at 13.6 points in the 150k to 200k band and 14.5 points above 200k. A Black applicant earning over 200,000 dollars is denied at 30.2 percent, which is higher than a White applicant earning between 50,000 and 100,000. Asian and Joint applicants, who together are more than half the combined other group, converge towards the White rate as income rises, and that convergence is what pulls the combined gap from 10.5 points down to 4.5. The aggregate is not wrong, it is just averaging two opposite movements.

---

## 6. Finding 5: it survives the product

Run live [▶ query 23](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=23)

```sql
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
```

| loan purpose | decided | overall denial | Black | White |
|---|---|---|---|---|
| Home purchase | 584,891 | 13.3% | 20.8% | 11.6% |
| Cash-out refinancing | 171,169 | 27.0% | 39.0% | 23.9% |
| Refinancing | 145,831 | 26.4% | 40.5% | 24.3% |
| Home improvement | 209,703 | 41.5% | **64.5%** | 34.7% |
| Other purpose | 159,076 | 44.1% | 62.4% | 38.5% |

**What this says.** Borrowing to buy a home is the easiest thing to be approved for and borrowing against a home you already own is the hardest. That holds for everyone. But in every one of the five products, the Black rate is above the White rate, so the gap is not explained by different groups wanting different kinds of loan.

Home improvement is the finding inside the finding. It is the second largest product in this market at 209,703 decided applications, it denies at 41.5 percent overall, and for Black applicants it denies at 64.5 percent. These are loans secured on a property the applicant already owns, to maintain or improve it.

---

## 7. Finding 6: it survives geography, measured two ways

Run live [▶ query 18](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=18)

```sql
WITH d AS (
  SELECT f.action_taken, t.minority_population_pct,
         CASE WHEN t.minority_population_pct <  20 THEN 'under 20%'
              WHEN t.minority_population_pct <  40 THEN '20 to 40%'
              WHEN t.minority_population_pct <  60 THEN '40 to 60%'
              WHEN t.minority_population_pct <  80 THEN '60 to 80%'
              ELSE                                       '80% and above'
         END AS minority_band
  FROM marts.fct_application f
  JOIN marts.dim_tract t
    ON t.activity_year = f.activity_year AND t.census_tract = f.census_tract
  WHERE f.action_taken IN ('1','3')
    AND f.census_tract <> 'UNKNOWN'
    AND t.minority_population_pct IS NOT NULL)
SELECT minority_band AS tract_minority_population,
       count(*)      AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3')/count(*), 1) AS denial_rate
FROM d GROUP BY 1 ORDER BY min(minority_population_pct);
```

First, denial rises with the minority share of the neighbourhood:

| tract minority population | decided | denial rate |
|---|---|---|
| under 20% | 517,898 | 21.7% |
| 20 to 40% | 373,937 | 23.6% |
| 40 to 60% | 139,453 | 26.2% |
| 60 to 80% | 90,730 | 28.9% |
| 80% and above | 141,904 | 37.2% |

**What this says.** The more non-White a neighbourhood is, the more often applications there are refused, and the pattern is a steady climb rather than a jump at one end. On its own this proves nothing, because the people applying in those neighbourhoods also differ in income and in what they are borrowing for.

That gradient is consistent with either explanation, because applicants are not randomly distributed across tracts. So the stronger test is to compare applicants **within the same census tract**, which holds the neighbourhood, the local housing market and the local economy constant by construction.

Run live [▶ query 18b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=18b)

```sql
WITH g AS (
  SELECT f.census_tract, a.derived_race AS grp,
         count(*)                                     AS decided,
         count(*) FILTER (WHERE f.action_taken = '3')  AS denied
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3')
    AND f.census_tract <> 'UNKNOWN'
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only')
  GROUP BY 1,2),
w AS (SELECT census_tract, decided AS white_decided,
             100.0*denied/decided AS rate_white
      FROM g WHERE grp = 'White'),
o AS (SELECT census_tract, grp, decided AS group_decided,
             100.0*denied/decided AS rate_group
      FROM g WHERE grp <> 'White'),
p AS (SELECT o.grp, o.rate_group - w.rate_white AS gap
      FROM o JOIN w ON w.census_tract = o.census_tract
      WHERE o.group_decided >= 100 AND w.white_decided >= 100)
SELECT grp                                             AS applicant_group,
       count(*)                                        AS tracts,
       count(*) FILTER (WHERE gap > 0)                 AS group_rate_higher,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY gap) AS numeric), 1) AS median_gap,
       round(CAST(min(gap) AS numeric), 1)             AS min_gap,
       round(CAST(max(gap) AS numeric), 1)             AS max_gap
FROM p
GROUP BY 1
ORDER BY 2 DESC, 1;
```

| applicant group | tracts | group rate higher | median gap | range |
|---|---|---|---|---|
| Asian | 102 | 23 of 102 | **−5.2** | −33.3 to +18.3 |
| Black or African American | 62 | **60 of 62** | **+10.9** | −2.6 to +23.8 |

**What this says.** This compares people applying on the same streets. In 60 of the 62 neighbourhoods where both groups applied in numbers, Black applicants were refused more often than White applicants, by about 11 points in the typical one. Two out of 62 going the other way is about what chance alone would produce. Asian applicants show the opposite pattern, refused *less* often than White applicants in most tracts, which is a reminder that "non-White" is not one group.

Only Asian and Black applicants appear, because the test requires 100 decided applications from each side in the same tract and no New York tract reaches that for the smaller groups. That is a limit of the data, not a finding about those groups.

---

## 8. Finding 7: it survives the lender

Run live [▶ query 24](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=24)

```sql
WITH d AS (
  SELECT i.institution_name AS lender, f.action_taken, a.derived_race,
         CASE WHEN a.derived_race = 'White' THEN 'W' ELSE 'O' END AS grp
  FROM marts.fct_application f
  JOIN marts.dim_institution i
    ON i.activity_year = f.activity_year AND i.lei = f.lei
  JOIN marts.dim_applicant_profile a
    ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3')
    AND a.derived_race NOT IN ('Race Not Available','Free Form Text Only'))
SELECT lender, count(*) AS decided,
  round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='W')
        /nullif(count(*) FILTER (WHERE grp='W'),0), 1) AS white,
  round(100.0*count(*) FILTER (WHERE action_taken='3' AND grp='O')
        /nullif(count(*) FILTER (WHERE grp='O'),0), 1) AS all_other,
  round(100.0*count(*) FILTER (WHERE action_taken='3'
                               AND derived_race='Black or African American')
        /nullif(count(*) FILTER (WHERE derived_race='Black or African American'),0), 1) AS black,
  round(100.0*count(*) FILTER (WHERE action_taken='3' AND derived_race='Asian')
        /nullif(count(*) FILTER (WHERE derived_race='Asian'),0), 1) AS asian
FROM d GROUP BY 1 ORDER BY 2 DESC LIMIT 6;
```

| lender | decided | White | all other reported races | Black | Asian |
|---|---|---|---|---|---|
| ROCKET MORTGAGE | 51,136 | 22.1% | 28.6% | 30.9% | 25.8% |
| CBNA Year to Date | 46,460 | 38.1% | 51.5% | 57.9% | 48.1% |
| United Wholesale Mortgage | 41,810 | 12.2% | 16.9% | 20.6% | 15.6% |
| M&T BANK | 40,537 | 29.4% | 45.4% | 49.1% | 38.2% |
| JPMorgan Chase Bank, NA | 37,990 | 12.8% | 15.0% | 20.9% | 12.8% |
| Bank of America NA | 31,128 | 46.2% | 60.5% | 65.3% | 57.8% |

**What this says.** These six lenders disagree enormously about how often to refuse anyone: 12.2 percent to 46.2 percent for White applicants, which is nearly a factor of four. They agree completely about the direction. Every one of them refuses the other group more often than White applicants. So the pattern is not one badly behaved lender, and it is not applicants choosing stricter lenders either, because it shows up inside each lender separately.

The `decided` column here counts only applications where a race was reported, so it is lower than the same lender's total decided count elsewhere in this phase. Rates computed on a denominator that includes unreported race would not be comparable between columns.

**Six of the largest lenders in the market, and every one of them denies the combined other group more often than it denies White applicants.** The gap runs from 2.2 points at JPMorgan Chase to 16.0 at M&T Bank, at ratios of 1.17 to 1.54. Taking Black applicants alone the gaps are wider and the ratios tighter: 8.1 to 19.8 points, at 1.40 to 1.69 times the lender's own White rate.

What makes this hard to explain away is the contrast between the two things that vary. The overall level of strictness varies enormously across these six, from 12.2 percent to 46.2 percent for White applicants alone. The direction of the gap does not vary at all. A generous lender and a strict lender disagree by 34 points about how often to say no, and agree about who hears it more often.

The generalisation is not perfectly uniform, and the exception is worth naming: at JPMorgan Chase the Asian and White rates are identical to one decimal place, at 12.8 percent, while its Black rate is 20.9. So "other races" is not one thing at the lender level either, which is the same caution as section 5. What survives in every cell of the table is that the combined other group is denied more often than White applicants. Whatever produces the pattern is not one outlier institution.

---

## 9. Finding 8: lenders differ from each other more than they differ from their own average

This one reframes everything above, and it is the most useful finding in the project for anyone who has to act.

Run live [▶ query 19](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=19)

```sql
WITH lt AS (
  SELECT census_tract, lei, count(*) AS decided,
         100.0*count(*) FILTER (WHERE action_taken='3')/count(*) AS rate
  FROM marts.fct_application
  WHERE action_taken IN ('1','3') AND census_tract <> 'UNKNOWN'
  GROUP BY 1,2
  HAVING count(*) >= 30)
SELECT count(*) AS tracts,
       round(CAST(percentile_cont(0.25) WITHIN GROUP (ORDER BY spread) AS numeric), 1) AS p25,
       round(CAST(percentile_cont(0.50) WITHIN GROUP (ORDER BY spread) AS numeric), 1) AS median,
       round(CAST(percentile_cont(0.75) WITHIN GROUP (ORDER BY spread) AS numeric), 1) AS p75,
       round(CAST(max(spread) AS numeric), 1)                                          AS max_spread
FROM (SELECT census_tract, max(rate)-min(rate) AS spread
      FROM lt GROUP BY 1 HAVING count(*) >= 4) s;
```

In the 532 census tracts where at least four lenders each made at least 30 decisions:

| tracts | p25 | median | p75 | max spread |
|---|---|---|---|---|
| 532 | 22.8 | **30.6** | 39.5 | **97.3** |

**What this says.** Pick a New York neighbourhood. Among the lenders active there, the strictest and the most generous are about 30 points apart on denial rate, and in the most extreme neighbourhood they are 97 points apart. That is a bigger difference than anything else in this document, including every gap between groups.

In a typical New York census tract, the most and least restrictive active lender are 30 points apart on the same neighbourhood. That dwarfs every group gap in this phase, the 8.3 points between White and all other reported races and the 17.2 points between White and Black applicants alike, and it dwarfs the 3.65 point four-year market movement.

It is also the finding with a direct implication, because it is the one an individual can act on: which lender an applicant approaches matters more than almost anything else measured here. And for a regulator it identifies exactly where to look, since "this lender is 30 points above its peers in the same tracts" is a specific, testable, peer-controlled claim rather than a market-wide average.

---

## 10. Finding 9: denial is not the only channel

4.47 percent of all applications, 78,521 of them, end in "file closed for incompleteness" rather than a decision. That is not a denial, so it is invisible to every number in this document.

Run live [▶ query 21](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=21)

```sql
SELECT i.institution_name,
       count(*)                                                          AS applications,
       round(100.0*count(*) FILTER (WHERE f.action_taken='5')/count(*),1) AS closed_incomplete_pct
FROM marts.fct_application f
JOIN marts.dim_institution i ON i.activity_year = f.activity_year AND i.lei = f.lei
GROUP BY 1
HAVING count(*) >= 20000
ORDER BY 3 DESC;
```

| lender (20,000+ applications) | closed for incompleteness |
|---|---|
| DISCOVER BANK | 28.5% |
| Bank of America NA | 11.2% |
| NEWREZ LLC | 9.3% |
| TD Bank | 7.3% |
| ... | ... |
| M&T BANK | 1.1% |
| Premium Mortgage Corporation | 0.8% |
| ROCKET MORTGAGE | 0.2% |

**What this says.** "Closed for incompleteness" means the application stopped without anyone deciding it, usually because paperwork was never completed. At one large bank that happens to more than a quarter of applicants and at another to one in five hundred. Same state, same years, same rules.

**0.2 percent to 28.5 percent, a factor of 142.** Two lenders in the same state, in the same years, under the same rules, differ this much in how often an application simply stops. Whatever that measures, it is not applicant behaviour, because applicant behaviour does not vary by a factor of 142 between two national banks.

And the channel is not neutral across groups. Note the denominator: this one is *all* applications, not decided ones, because the whole point is the outcomes that never reach a decision.

Run live [▶ query 21b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=21b)

```sql
WITH d AS (
  SELECT f.action_taken, a.derived_race,
         CASE WHEN a.derived_race = 'White' THEN 'White'
              WHEN a.derived_race IN ('Race Not Available','Free Form Text Only')
                   THEN 'Race not reported'
              ELSE 'All other reported races combined' END AS grp
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk)
SELECT coalesce(derived_race, grp) AS applicant_group,
       count(*)                   AS applications,
       round(100.0*count(*) FILTER (WHERE action_taken = '5')/count(*), 1) AS closed_incomplete_pct,
       round(100.0*count(*) FILTER (WHERE action_taken = '4')/count(*), 1) AS withdrawn_pct
FROM d
GROUP BY GROUPING SETS ((derived_race), (grp))
HAVING derived_race IS NOT NULL
    OR grp = 'All other reported races combined'
ORDER BY (derived_race IS NULL), 2 DESC;
```

| group | applications | closed for incompleteness | withdrawn by applicant |
|---|---|---|---|
| White | 1,005,207 | 4.3% | 10.7% |
| *Race not available* | 429,153 | *4.1%* | *10.4%* |
| Asian | 150,518 | 5.7% | 13.1% |
| Black or African American | 127,176 | 5.6% | 13.2% |
| Joint | 28,007 | 3.8% | 12.4% |
| American Indian or Alaska Native | 6,903 | **9.0%** | 12.2% |
| 2 or more minority races | 3,870 | 8.3% | 12.1% |
| Native Hawaiian or Other Pacific Islander | 3,373 | 5.5% | 12.0% |
| *Free form text only* | 639 | *7.4%* | *10.6%* |
| **All other reported races combined** | 319,847 | **5.6%** | **13.0%** |

**What this says.** The last row is produced by the same query as the rows above it, using `GROUPING SETS`, rather than being added by hand afterwards. Applications from the other group stop short of a decision slightly more often than White applications do, and are withdrawn slightly more often. Both gaps are smaller than the denial gap, and both lean the same way.

Against White applicants at 4.3 percent and 10.7 percent, the combined other group is closed for incompleteness 1.3 points more often and withdraws 2.3 points more often. Both are smaller gaps than the denial gap, and both point the same way.

The row that stands out is American Indian or Alaska Native applicants at 9.0 percent, more than twice the White rate, on 6,903 applications. That group is also the second most often denied. The two channels are not substituting for each other, they are stacking.

A fair-lending review that looks only at denial rates misses this entirely. Adding one outcome code to the analysis surfaces a channel roughly a third the size of denial itself.

### 10.1 The reason given for a denial differs by group

Phase 08 section 12 shows that debt-to-income is the largest single reason for denial across the whole market, at 36.7 percent. Splitting the same primary reasons by group shows the mix is not the same for everyone.

Run live [▶ query 21c](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=21c)

```sql
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
```

Share of each group's denials, by the primary reason given:

| group | denials with a reason | debt-to-income | credit history | collateral |
|---|---|---|---|---|
| White | 181,299 | 37.0% | 23.9% | 16.9% |
| *Race not available* | 63,184 | *33.6%* | *20.8%* | *17.3%* |
| Black or African American | 38,273 | 36.7% | **28.3%** | 14.1% |
| Asian | 27,177 | **42.6%** | **14.9%** | 17.8% |
| Joint | 4,056 | 30.3% | 27.4% | **20.2%** |
| American Indian or Alaska Native | 2,482 | 37.1% | 30.0% | 13.3% |
| 2 or more minority races | 1,409 | 36.2% | 30.7% | 13.8% |
| Native Hawaiian or Other Pacific Islander | 1,266 | **47.0%** | 25.4% | 10.7% |

**What this says.** Everyone in this table was refused. The columns describe what they were told the reason was. The rows do not sum to 100 percent because only the three most common reasons are shown. Debt-to-income means the monthly payments were judged too large for the income; credit history means the borrowing record; collateral means the property itself.

**Black applicants who are denied are more likely than White applicants to be told the reason was credit history, 28.3 percent against 23.9.** Asian applicants are the reverse: 14.9 percent on credit history, the lowest in the table, and 42.6 percent on debt-to-income, the highest of any large group.

This is a compositional finding, not a causal one, and the direction of the inference matters. It does not show that lenders apply credit history differently. It shows that among applicants who were refused, the stated reason differs by group, which is consistent with several explanations including different underlying application profiles. What it does establish is that a single market-wide denial reason breakdown, of the kind phase 08 presents, hides variation of eight to thirteen points between groups.

One limitation is specific to this table. HMDA does not require a denial reason from every filer, and the exempt code 1111 that phase 08 names is unevenly distributed across lenders. Groups that concentrate at exempt filers will be under-represented here in ways this table cannot show.

---

## 11. Pricing, not just access

For loans that were actually originated, `rate_spread` is the difference between the APR and the market benchmark rate, so it measures price rather than access.

Run live [▶ query 25](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=25)

```sql
SELECT a.derived_race AS applicant_group,
       count(*)       AS originated_with_spread,
       round(CAST(avg(f.rate_spread) AS numeric), 3) AS mean_spread,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.rate_spread)
             AS numeric), 3)                         AS median_spread
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1' AND f.rate_spread IS NOT NULL
GROUP BY 1 ORDER BY 4, 1;
```

| group | originated with a spread | mean spread | median spread |
|---|---|---|---|
| Joint | 16,485 | 0.143 | **0.093** |
| Asian | 73,618 | 0.202 | 0.116 |
| *Race not available* | 112,097 | *0.392* | *0.219* |
| 2 or more minority races | 1,378 | 0.360 | 0.250 |
| White | 540,734 | 0.278 | 0.250 |
| Native Hawaiian or Other Pacific Islander | 1,210 | 0.525 | 0.374 |
| American Indian or Alaska Native | 2,410 | 0.456 | 0.400 |
| Black or African American | 51,958 | 0.493 | **0.441** |
| *Free form text only* | 177 | *0.712* | *0.500* |

**What this says.** A rate spread of 0.25 means the loan's APR was a quarter of a percentage point above the going rate for a comparable loan at that time. These are the borrowers who were approved, so access is no longer the question. Black borrowers paid a median premium of 0.441 against 0.250 for White borrowers, on loans the same size and type. *Free form text only* is shown because the query returns it, but at 177 loans it carries no weight and it is not a race category.

**The distance between the top and the bottom of this table is the widest in the phase.** The median spread runs from 0.093 for Joint applicants to 0.441 for Black applicants, a factor of 4.7, and from 0.116 for Asian applicants, a factor of 3.8. White sits in the middle at 0.250, which makes the Black median 1.8 times the White median and the Black mean 1.8 times the White mean. On means the range is 0.143 to 0.525.

The median matters more than the mean here, because a mean can be moved by a handful of extreme loans and a median cannot. Both agree, which is the point of showing them together.

This is also the one place in the phase where combining all non-White groups would actively mislead, and it is worth stating plainly rather than quietly using a different method. Taken together, all other reported races pay a median spread of **0.226, which is lower than the White median of 0.250**, because Asian and Joint borrowers are numerous and priced far below everyone else. The aggregate reverses the sign of a large, real effect on Black borrowers. Where a combined comparison is used elsewhere in this phase it is used because it is the conservative choice; on pricing it would simply be the wrong one.

Note also that this is a conditional comparison on a selected group: these are the applicants who got through, which if anything understates the effect.

### 11.1 The interest rate says something different from the rate spread

`rate_spread` is the difference between the loan's APR and the market benchmark for a comparable loan, so it already adjusts for product and timing. `interest_rate` is the raw number on the note and adjusts for nothing. Running the same comparison on the raw rate, within 2025 so the rate environment is held constant:

Run live [▶ query 25b](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=25b)

```sql
SELECT a.derived_race AS applicant_group,
       count(*)       AS loans,
       round(CAST(avg(f.interest_rate) AS numeric), 3) AS mean_rate_pct,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS numeric), 3)                       AS median_rate_pct
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1' AND f.interest_rate IS NOT NULL AND f.activity_year = 2025
GROUP BY 1 ORDER BY 4, 1;
```

| group, 2025 originations | loans | mean rate | median rate |
|---|---|---|---|
| *Free form text only* | 29 | *6.250%* | *6.250%* |
| Asian | 19,963 | 6.593% | **6.490%** |
| 2 or more minority races | 461 | 6.678% | 6.499% |
| Joint | 4,314 | 6.573% | 6.500% |
| American Indian or Alaska Native | 697 | 6.822% | 6.624% |
| Black or African American | 13,436 | **6.857%** | 6.625% |
| Native Hawaiian or Other Pacific Islander | 288 | 6.879% | 6.625% |
| White | 148,624 | 6.727% | 6.625% |
| *Race not available* | 36,261 | *7.037%* | *6.750%* |

**What this says.** This is the rate printed on the loan document, with no adjustment for what kind of loan it is. Three of the groups, including Black and White borrowers, share the same median of 6.625 percent. The gap in the previous table has not disappeared: it was never in the headline rate, it was in how far above the going rate for that particular loan the borrower ended up. *Free form text only* appears at 29 loans and should be read as noise.

**On the raw rate, the Black and White medians are identical at 6.625 percent.** On the mean, Black borrowers pay 13 basis points more. That is a far smaller difference than the 1.8 times on rate spread, and it is not a contradiction: the two columns measure different things. A borrower can pay the same headline rate as someone else and still be paying well above the benchmark for their product, term and timing, which is exactly what rate spread captures and the raw rate does not.

Reported here because it would be easy to quote only the rate spread version. The honest statement is that the gap is in the premium over benchmark, not in the coupon.

---

## 12. What this analysis cannot say

Stated here rather than at the end of a press release.

**There is no credit score in HMDA.** The regulator does not collect it. It is the single strongest legitimate predictor of a credit decision and it is absent from every number above. So no finding here is causal, and none of it establishes discrimination, which is a legal conclusion requiring evidence this dataset does not contain.

What the data does support is narrower and still substantial: the disparity is not explained by income, product, neighbourhood or lender choice, because it persists after holding each of those constant. Whether it is explained by creditworthiness cannot be tested with this data, and any conclusion in either direction is an assumption rather than a finding.

**Race is unreported for 24.5 percent of all 1,754,846 rows.** Every group comparison is computed on the three quarters who reported. The direction of that bias is unknown.

**Vintages are mixed.** 2022 is a Three Year file, 2023 and 2024 are One Year files, 2025 is provisional. Some of any year-on-year movement is filing completeness. Phase 01 section 4 has the detail.

**One state.** New York is not the United States.

---

## 13. The SQL this phase actually exercises

| technique | where it earns its place |
|---|---|
| `FILTER (WHERE ...)` aggregates | every rate in this document, computed in one pass instead of self-joins |
| `GROUPING SETS` | query 21b returns the per-group rows and the combined comparison row from one pass, so the summary row cannot drift from the detail |
| Window functions | `sum(count(*)) OVER ()` for the outcome shares in query 14, and the share-of-total columns in the general analysis |
| CTEs, several deep | the shift-share decomposition in 17 and 17b, and the within-tract comparison in 18b |
| `percentile_cont` ordered-set aggregates | the quartiles in query 19, the median gap in 18b, the median spread and rate in 25 and 25b |
| Conditional pivots | income bands and minority bands turned into columns in 16 and 16b without a self-join |
| Bridge-table joins | query 20, which counts individual reported races rather than `derived_race` |
| Partial indexes and partition pruning | phase 09 shows the plans |

Two notes on what is *not* in that list. The assertion queries that use correlated `NOT EXISTS` live in phase 07, not here. And the queries in this phase read the fact and dimension tables directly rather than the phase 05 views, so the code literal `'3'` does appear in them; the views exist for the catalogue and the playground, and the one place this phase uses a view is `marts.v_denial_reason` in query 21c.

---

## 14. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| `denied / (originated + denied)` | denied over all applications | the other six outcomes are not credit decisions |
| Shift-share before explaining a trend | a plausible narrative | my own plausible narrative was backwards |
| Within-tract comparison | tract minority share as a control | holds the neighbourhood constant by construction, not by regression |
| Per-lender comparison | market aggregate | rules out the single-outlier explanation |
| Reporting the incompleteness channel | denial rates only | a factor of 142 between lenders is not a footnote |
| Median as well as mean on pricing | mean alone | a mean on a skewed distribution is movable by a few loans |
| Reporting group gaps both combined and per group | one or the other | they disagree on income and reverse on pricing, and hiding that would be a choice about the conclusion |
| Excluding unreported race from both sides of a comparison | leaving it in one side | otherwise the result measures who declined to answer |
| Showing rate spread and raw interest rate side by side | rate spread alone | they disagree, and the disagreement is the finding |
| Gap columns as the difference of the displayed figures | the difference of the unrounded figures | a reader can check the arithmetic in the table in front of them |
| `percentile_disc` for the median price | `percentile_cont` | rates are quoted in eighths, so an interpolated midpoint is a price nobody was charged, and interpolation is the one place the two engines can disagree |
| Stating the missing credit score repeatedly | one caveat at the end | it is the boundary of every claim here, not a disclaimer |
