# Mortgage Lending in New York, 2022 to 2025

**[Open the Playground](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/)** · **[Browse the Data Dictionary](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/catalog/)** · **[See the ERD](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/erd/)** · **[Project Home](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/)**

1,596,676 mortgage applications filed in New York State between 2022 and 2025
under the US Home Mortgage Disclosure Act, modelled into a dimensional warehouse
and analysed in forty-two SQL queries. Every figure on this page comes from a
query printed beside it, and every query runs in your browser against the real
data: 1.75 million rows, no install, no account, nothing sent to a server.

---

## Contents

- [How to Read This Page](#how-to-read-this-page)
- [A. Mortgage Market Overview](#a-mortgage-market-overview) · seven queries
- [B. Mortgage Market Trends, Year on Year](#b-mortgage-market-trends-year-on-year) · two queries
- [C. Applicant Demographics: Affordability and Borrowing](#c-applicant-demographics-affordability-and-borrowing) · eleven queries
- [D. Mortgage Denial Analysis](#d-mortgage-denial-analysis) · six queries
- [E. Lender Performance](#e-lender-performance) · twelve queries
- [F. Recommendations](#f-recommendations) · four queries
- [The Data Model](#the-data-model)
- [Where the Data Comes From](#where-the-data-comes-from)
- [How the Numbers Are Checked](#how-the-numbers-are-checked)
- [Author](#author)

---

## How to Read This Page

Each section below is collapsed. Open the one you want. Inside, every query
carries its result, its SQL and a short reading of what the result says, and the
SQL is collapsed again so an open section shows prose and tables until you ask
for the code.

**Conventions apply throughout, and they decide most of the numbers.**

**Purchased loans are excluded everywhere.** HMDA action code 6 records a loan a
bank bought after another institution made it. The buyer made no decision, so
the row belongs in neither the numerator nor the denominator of a decision rate.
Including it would dilute every rate on this page by the volume of the secondary
market. 158,743 rows are excluded on this rule, leaving 1,596,676.

**Medians use `percentile_disc`, not `percentile_cont`.** The continuous version
interpolates between the two middle rows and returns a figure no borrower was
charged; it also made PostgreSQL and DuckDB disagree in the third decimal on one
query during an earlier phase of this project. The discrete version returns a
value that is actually in the data and is exact in both engines.

**Nothing on this page is causal, and the reason is specific.** HMDA records what
lenders decided and the reasons they wrote down. It holds no credit score, no
assets, no employment record. So a difference between two groups or two lenders
is a difference in outcomes, and nothing here isolates the decision that produced
it.

---

## A. Mortgage Market Overview

<details>
<summary><b>Seven queries: overall market KPIs, then what the register covers by loan type, purpose and geography</b></summary>

Two subsections. **Overall market KPIs** is A1 and A2, the whole register in two
rows. **Dataset coverage and market profile** is A3 to A7, which says what is in
the register and how the market divides by product and by place.

Every other section on this page reconciles to A1. If a table's counts sum to
1,596,676 applications, 951,371 originated loans and 371,417,740,000 dollars,
it is covering the same population.

### A1. Volume, Money and How Applications End

| total_applications | total_originated_loans | total_loan_amount | approval_rate | denial_rate | incomplete_rate | withdrawal_rate |
|---|---|---|---|---|---|---|
| 1,596,676 | 951,371 | 371,417,740,000 | 62.85 | 20.09 | 4.92 | 12.14 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A1">Query A1</a></summary>

```sql
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
```

</details>

Total applications counts every application filed with a New York lender between
2022 and 2025, purchased loans excluded. Total originated loans counts those that
became a loan: the lender approved it **and** the applicant took it.

Approval and origination are not the same event, which is why the approval rate
of 62.85 percent is higher than originations divided by applications. 45,177
applications were approved and then declined by the applicant, and a further
6,982 were preapprovals approved and never taken up. Those are approvals and they
are not loans.

Total loan amount sums originated loans only. It is money that actually moved.
Summing across all applications would add in loans that were never made.

**Three applications in five became a loan. One in five was refused. The
remaining one in six ended with no decision at all**, split between applicants
who withdrew, 12.14 percent, and files closed for incompleteness, 4.92 percent.
That last group is carried through every table on this page. It is a quarter the
size of the denial rate, and an analysis that looks only at approvals and denials
never sees it.

### A2. The Typical Loan That Was Made

| originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|
| 951,371 | 127,000 | 475,000 | 245,000 | 75.00 | 1.96 | 6.281 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A2">Query A2</a></summary>

```sql
SELECT count(*)                                                        AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                        AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY property_value)
             AS DECIMAL(24,8)))                                        AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_amount)
             AS DECIMAL(24,8)))                                        AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                     AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN loan_amount / (income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                     AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY interest_rate)
             AS DECIMAL(24,8)), 3)                                     AS median_interest_rate
FROM marts.fct_application
WHERE action_taken = '1';
```

</details>

Originated loans only. A denied application has no interest rate, usually no
agreed amount and often no property value, so a median taken across every
application would be a median of whatever happened to be filled in.

The columns run applicant, then asset, then loan, then the two ratios, then
price. That order is used in every table of medians on this page, so the same
column is always in the same place.

Median applicant income excludes rows reporting zero or a negative figure. A
reported income of zero is a missing value, not an income, and loan-to-income
has to exclude them anyway because you cannot divide by zero. Treating the two
columns differently would put two populations in one row.

**Loan-to-value is the ratio as the lender filed it, and it is not loan divided
by property value.** Tested by lien status: on first liens the filed ratio reads
76.77 against 76.47 computed from the two columns, which agree. On subordinate
liens the filed ratio reads 69.59 against 18.92 computed, and the filed figure is
higher on 99.0 percent of rows. The filed ratio counts every lien on the
property, not only the loan in that row, which is what a lender needs to know and
is why it is the one reported here.

Median interest rate is pooled across four years in which the market median moved
237.5 basis points. [B2](#b2-the-typical-loan-that-was-made-by-year) is where
that pooling is unpacked, and no rate on this page is read without it.

### A3. What the Register Covers

| ord | metric | value |
|---|---|---|
| 1 | Years covered | 4 |
| 2 | Distinct lenders | 1,168 |
| 3 | Distinct New York counties | 62 |
| 4 | Distinct census tracts | 5,281 |
| 5 | Distinct loan types | 4 |
| 6 | Distinct loan purposes | 6 |
| 7 | Distinct sex values | 4 |
| 8 | Distinct race values | 9 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A3">Query A3</a></summary>

```sql
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
  (1, 'Years covered',           CAST(f.years_covered  AS BIGINT)),
  (2, 'Distinct lenders',        CAST(f.lenders        AS BIGINT)),
  (3, 'Distinct New York counties', CAST(f.ny_counties AS BIGINT)),
  (4, 'Distinct census tracts',  CAST(f.tracts         AS BIGINT)),
  (5, 'Distinct loan types',     CAST(p.loan_types     AS BIGINT)),
  (6, 'Distinct loan purposes',  CAST(p.loan_purposes  AS BIGINT)),
  (7, 'Distinct sex values',     CAST(d.sex_values     AS BIGINT)),
  (8, 'Distinct race values',    CAST(d.race_values    AS BIGINT))
) AS v(ord, metric, value)
ORDER BY v.ord;
```

</details>

Years covered is the number of distinct filing years. 2022 is a three-year file,
2023 and 2024 are one-year files and 2025 is the provisional vintage, so the four
are not equally complete.
[Section B](#b-mortgage-market-trends-year-on-year) says where that matters.

Distinct lenders counts unique Legal Entity Identifiers, so it is a count of
institutions rather than of brands or branches.

**Distinct New York counties is 62, which is every county in the state.** The raw
column returns 66, because it also contains an UNKNOWN value and three codes
outside New York filed against New York properties. Counting those would have
claimed four counties that do not exist, so the column is restricted to codes
beginning 36, which is New York's state FIPS prefix.

Distinct census tracts excludes the same UNKNOWN value, which is why it reads
5,281 rather than 5,282. Every tract count elsewhere on this page uses the same
exclusion.

Four loan types and six loan purposes are the regulator's full sets, and
[A4](#a4-market-profile-by-loan-type) and
[A5](#a5-market-profile-by-loan-purpose) break the market down by each.

### A4. Market Profile by Loan Type

| loan_type | total_applications | pct_of_applications | originated_loans | pct_of_originated_loans | median_loan_amount | total_loan_amount |
|---|---|---|---|---|---|---|
| Conventional (not insured or guaranteed by FHA, VA, RHS, or FSA) | 1,434,757 | 89.86 | 857,341 | 90.12 | 235,000 | 338,378,090,000 |
| Federal Housing Administration insured (FHA) | 123,790 | 7.75 | 70,637 | 7.42 | 285,000 | 25,438,615,000 |
| Veterans Affairs guaranteed (VA) | 36,199 | 2.27 | 22,037 | 2.32 | 275,000 | 7,398,285,000 |
| USDA Rural Housing Service or Farm Service Agency guaranteed (RHS or FSA) | 1,930 | 0.12 | 1,356 | 0.14 | 145,000 | 202,750,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A4">Query A4</a></summary>

```sql
SELECT r.label                                                              AS loan_type,
       count(*)                                                            AS total_applications,
       round(CAST(100.0 * count(*) AS DECIMAL(24,8))
             / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 2)            AS pct_of_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                        AS originated_loans,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                           AS pct_of_originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_amount END)
             AS DECIMAL(24,8)))                                             AS median_loan_amount,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)  AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code r
  ON r.code_field = 'loan_type'
 AND r.code_value = p.loan_type
WHERE f.action_taken <> '6'
GROUP BY r.label
ORDER BY 2 DESC;
```

</details>

**Two share columns, and the pair is the point.** Share of applications is what
the market asked for; share of originated loans is what it made. They differ by
however much the categories differ in how often they complete, so reading them
side by side gives the origination rate without a column for it.

On loan type the two sit within 0.33 of a point of each other on every row, and
that is the finding: **the four types complete at close to the same rate**,
between 57.06 and 70.26 percent. Conventional lending is 89.86 percent of
applications and 90.12 percent of loans.

What does differ is size. The median FHA loan is 285,000 dollars against 235,000
conventional, so FHA loans run larger at the median while conventional lending
holds 91.1 percent of the dollars on 90.12 percent of the loans. USDA lending is
0.12 percent of applications with a median loan of 145,000, the smallest of the
four.

### A5. Market Profile by Loan Purpose

| loan_purpose | total_applications | pct_of_applications | originated_loans | pct_of_originated_loans | median_loan_amount | total_loan_amount |
|---|---|---|---|---|---|---|
| Home purchase | 733,126 | 45.92 | 507,155 | 53.31 | 345,000 | 240,493,520,000 |
| Home improvement | 247,663 | 15.51 | 122,689 | 12.90 | 85,000 | 15,936,855,000 |
| Cash-out refinancing | 231,963 | 14.53 | 125,037 | 13.14 | 235,000 | 48,551,445,000 |
| Other purpose | 195,592 | 12.25 | 88,983 | 9.35 | 95,000 | 17,453,505,000 |
| Refinancing | 188,094 | 11.78 | 107,368 | 11.29 | 205,000 | 48,890,590,000 |
| Not applicable | 238 | 0.01 | 139 | 0.01 | 205,000 | 91,825,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A5">Query A5</a></summary>

```sql
SELECT r.label                                                              AS loan_purpose,
       count(*)                                                            AS total_applications,
       round(CAST(100.0 * count(*) AS DECIMAL(24,8))
             / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 2)            AS pct_of_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                        AS originated_loans,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                           AS pct_of_originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_amount END)
             AS DECIMAL(24,8)))                                             AS median_loan_amount,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)  AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code r
  ON r.code_field = 'loan_purpose'
 AND r.code_value = p.loan_purpose
WHERE f.action_taken <> '6'
GROUP BY r.label
ORDER BY 2 DESC;
```

</details>

**Here the two share columns come apart, and the gap is the most useful thing in
the table.** Home purchase is 45.92 percent of applications and 53.31 percent of
originated loans. Home improvement is 15.51 and 12.90. Other purpose is 12.25 and
9.35.

The categories do not complete at the same rate, so **the market that gets made
is a different shape from the market that gets asked for**. Where share of
originations exceeds share of applications the purpose completes above the market
average; where it falls short it completes below.
[D3](#d3-denial-reason-by-loan-purpose) and
[F4](#f4-how-much-choice-a-borrower-has-by-purpose) show how far: home purchase
denies at 10.78 percent against 35.13 for home improvement and 35.84 for other
purpose.

Size separates them again. The median home purchase loan is 345,000 dollars and
the median home improvement loan 85,000, a factor of four, so home improvement is
15.51 percent of applications and 4.29 percent of the dollars.

**Most lending in this register is not a house purchase.** Purchases are 53.31
percent of loans and everything else is the other 46.69, which is worth holding
in mind before reading any table that mixes purposes together.

### A6. The Ten Most Expensive Census Tracts

| census_tract | county_name | originated_loans | median_property_value | median_loan_amount | median_applicant_income |
|---|---|---|---|---|---|
| 36103190712 | Suffolk County | 297 | 6,415,000 | 2,435,000 | 1,160,000 |
| 36103200901 | Suffolk County | 240 | 6,105,000 | 2,355,000 | 1,150,000 |
| 36103190801 | Suffolk County | 275 | 5,405,000 | 2,085,000 | 1,050,000 |
| 36061013000 | New York County | 192 | 5,005,000 | 1,785,000 | 1,108,000 |
| 36061004700 | New York County | 114 | 4,995,000 | 2,535,000 | 1,000,000 |
| 36061003900 | New York County | 379 | 4,205,000 | 2,205,000 | 877,000 |
| 36061009901 | New York County | 254 | 4,075,000 | 2,005,000 | 839,000 |
| 36103201006 | Suffolk County | 285 | 4,005,000 | 1,505,000 | 805,000 |
| 36061003300 | New York County | 348 | 3,855,000 | 2,045,000 | 830,000 |
| 36061004900 | New York County | 197 | 3,705,000 | 1,755,000 | 645,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A6">Query A6</a></summary>

```sql
WITH county (county_code, county_name) AS (
    VALUES ('36001', 'Albany County'),
           ('36003', 'Allegany County'),
           ('36005', 'Bronx County'),
           ('36007', 'Broome County'),
           ('36009', 'Cattaraugus County'),
           ('36011', 'Cayuga County'),
           ('36013', 'Chautauqua County'),
           ('36015', 'Chemung County'),
           ('36017', 'Chenango County'),
           ('36019', 'Clinton County'),
           ('36021', 'Columbia County'),
           ('36023', 'Cortland County'),
           ('36025', 'Delaware County'),
           ('36027', 'Dutchess County'),
           ('36029', 'Erie County'),
           ('36031', 'Essex County'),
           ('36033', 'Franklin County'),
           ('36035', 'Fulton County'),
           ('36037', 'Genesee County'),
           ('36039', 'Greene County'),
           ('36041', 'Hamilton County'),
           ('36043', 'Herkimer County'),
           ('36045', 'Jefferson County'),
           ('36047', 'Kings County'),
           ('36049', 'Lewis County'),
           ('36051', 'Livingston County'),
           ('36053', 'Madison County'),
           ('36055', 'Monroe County'),
           ('36057', 'Montgomery County'),
           ('36059', 'Nassau County'),
           ('36061', 'New York County'),
           ('36063', 'Niagara County'),
           ('36065', 'Oneida County'),
           ('36067', 'Onondaga County'),
           ('36069', 'Ontario County'),
           ('36071', 'Orange County'),
           ('36073', 'Orleans County'),
           ('36075', 'Oswego County'),
           ('36077', 'Otsego County'),
           ('36079', 'Putnam County'),
           ('36081', 'Queens County'),
           ('36083', 'Rensselaer County'),
           ('36085', 'Richmond County'),
           ('36087', 'Rockland County'),
           ('36089', 'St. Lawrence County'),
           ('36091', 'Saratoga County'),
           ('36093', 'Schenectady County'),
           ('36095', 'Schoharie County'),
           ('36097', 'Schuyler County'),
           ('36099', 'Seneca County'),
           ('36101', 'Steuben County'),
           ('36103', 'Suffolk County'),
           ('36105', 'Sullivan County'),
           ('36107', 'Tioga County'),
           ('36109', 'Tompkins County'),
           ('36111', 'Ulster County'),
           ('36113', 'Warren County'),
           ('36115', 'Washington County'),
           ('36117', 'Wayne County'),
           ('36119', 'Westchester County'),
           ('36121', 'Wyoming County'),
           ('36123', 'Yates County')
)
SELECT f.census_tract,
       c.county_name,
       count(*)                                                      AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                      AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                      AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands * 1000)
             AS DECIMAL(24,8)))                                      AS median_applicant_income
FROM marts.fct_application f
LEFT JOIN county c ON c.county_code = left(f.census_tract, 5)
WHERE f.action_taken = '1'
  AND f.property_value IS NOT NULL
  AND f.census_tract <> 'UNKNOWN'
GROUP BY 1, 2
HAVING count(*) >= 100
ORDER BY 4 DESC, 1
LIMIT 10;
```

</details>

A census tract is a neighbourhood of a few thousand people, and it is the finest
geography HMDA publishes. Ranked here by median property value on originated
loans, with a floor of 100 loans so that a tract with three expensive sales
cannot top the table.

County names are joined from a reference table built for this project, because
**the register contains county FIPS codes and no county names at all**. Without
it this table would repeat a five-digit code in place of a place.

Suffolk County appears repeatedly, which is the Hamptons. The top tract records a
median property value of 6,415,000 dollars across 297 originated loans, thirteen
times the state median of 475,000.

### A7. The Ten Most Expensive Counties

| county_name | county_code | originated_loans | median_property_value | median_loan_amount | median_applicant_income |
|---|---|---|---|---|---|
| New York County | 36061 | 35,463 | 1,355,000 | 755,000 | 336,000 |
| Kings County | 36047 | 53,975 | 1,165,000 | 635,000 | 189,000 |
| Queens County | 36081 | 57,169 | 805,000 | 465,000 | 138,000 |
| Westchester County | 36119 | 48,759 | 765,000 | 435,000 | 200,000 |
| Nassau County | 36059 | 77,311 | 755,000 | 455,000 | 175,000 |
| Bronx County | 36005 | 15,927 | 725,000 | 475,000 | 127,000 |
| Richmond County | 36085 | 21,381 | 705,000 | 415,000 | 132,000 |
| Rockland County | 36087 | 18,747 | 695,000 | 415,000 | 165,000 |
| Suffolk County | 36103 | 105,735 | 635,000 | 385,000 | 152,000 |
| Putnam County | 36079 | 7,099 | 525,000 | 295,000 | 148,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=A7">Query A7</a></summary>

```sql
WITH county (county_code, county_name) AS (
    VALUES ('36001', 'Albany County'),
           ('36003', 'Allegany County'),
           ('36005', 'Bronx County'),
           ('36007', 'Broome County'),
           ('36009', 'Cattaraugus County'),
           ('36011', 'Cayuga County'),
           ('36013', 'Chautauqua County'),
           ('36015', 'Chemung County'),
           ('36017', 'Chenango County'),
           ('36019', 'Clinton County'),
           ('36021', 'Columbia County'),
           ('36023', 'Cortland County'),
           ('36025', 'Delaware County'),
           ('36027', 'Dutchess County'),
           ('36029', 'Erie County'),
           ('36031', 'Essex County'),
           ('36033', 'Franklin County'),
           ('36035', 'Fulton County'),
           ('36037', 'Genesee County'),
           ('36039', 'Greene County'),
           ('36041', 'Hamilton County'),
           ('36043', 'Herkimer County'),
           ('36045', 'Jefferson County'),
           ('36047', 'Kings County'),
           ('36049', 'Lewis County'),
           ('36051', 'Livingston County'),
           ('36053', 'Madison County'),
           ('36055', 'Monroe County'),
           ('36057', 'Montgomery County'),
           ('36059', 'Nassau County'),
           ('36061', 'New York County'),
           ('36063', 'Niagara County'),
           ('36065', 'Oneida County'),
           ('36067', 'Onondaga County'),
           ('36069', 'Ontario County'),
           ('36071', 'Orange County'),
           ('36073', 'Orleans County'),
           ('36075', 'Oswego County'),
           ('36077', 'Otsego County'),
           ('36079', 'Putnam County'),
           ('36081', 'Queens County'),
           ('36083', 'Rensselaer County'),
           ('36085', 'Richmond County'),
           ('36087', 'Rockland County'),
           ('36089', 'St. Lawrence County'),
           ('36091', 'Saratoga County'),
           ('36093', 'Schenectady County'),
           ('36095', 'Schoharie County'),
           ('36097', 'Schuyler County'),
           ('36099', 'Seneca County'),
           ('36101', 'Steuben County'),
           ('36103', 'Suffolk County'),
           ('36105', 'Sullivan County'),
           ('36107', 'Tioga County'),
           ('36109', 'Tompkins County'),
           ('36111', 'Ulster County'),
           ('36113', 'Warren County'),
           ('36115', 'Washington County'),
           ('36117', 'Wayne County'),
           ('36119', 'Westchester County'),
           ('36121', 'Wyoming County'),
           ('36123', 'Yates County')
)
SELECT c.county_name,
       f.county_code,
       count(*)                                                      AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                      AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                      AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.income_thousands * 1000)
             AS DECIMAL(24,8)))                                      AS median_applicant_income
FROM marts.fct_application f
JOIN county c ON c.county_code = f.county_code
WHERE f.action_taken = '1' AND f.property_value IS NOT NULL
GROUP BY 1, 2
HAVING count(*) >= 500
ORDER BY 4 DESC, 2
LIMIT 10;
```

</details>

The same measure one level up. 62 counties, no volume floor needed, since the
smallest county in the state still carries enough loans for a stable median.

New York County, which is Manhattan, records a median property value of 1,355,000
dollars. The state median is 475,000, so the median Manhattan property in this
register is 2.85 times the median New York State property.

The spread across counties is the single largest geographic effect in the data
and it sits behind several findings later on. Any table that compares applicant
groups without holding location constant is partly reading this map:
[C1b](#c1b-loan-characteristics-by-applicant-race) says where that matters most.

</details>

---

## B. Mortgage Market Trends, Year on Year

<details>
<summary><b>Two queries: volume and money by year, and the loan profile by year</b></summary>

**The four years are not equally complete and the difference is structural.**
2022 is a three-year file, 2023 and 2024 are one-year files, and 2025 is the
provisional vintage, published before the final one. No trend claim on this page
rests on 2025 alone.

These two queries are A1 and A2 cut by year, deliberately, so the market totals
and the yearly series cannot disagree.

### B1. Volume, Money and How Applications End, by Year

| activity_year | total_applications | total_originated_loans | total_loan_amount | approval_rate | denial_rate | incomplete_rate | withdrawal_rate |
|---|---|---|---|---|---|---|---|
| 2,022 | 500,553 | 307,252 | 128,518,325,000 | 64.39 | 18.69 | 4.32 | 12.60 |
| 2,023 | 346,943 | 203,072 | 72,698,435,000 | 61.72 | 21.68 | 4.82 | 11.77 |
| 2,024 | 355,249 | 208,814 | 76,890,970,000 | 61.94 | 21.02 | 5.17 | 11.88 |
| 2,025 | 393,931 | 232,233 | 93,310,010,000 | 62.71 | 19.63 | 5.53 | 12.13 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=B1">Query B1</a></summary>

```sql
SELECT activity_year,
       count(*)                                                        AS total_applications,
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
FROM marts.fct_application
WHERE action_taken <> '6'
GROUP BY 1
ORDER BY 1;
```

</details>

Applications fell 30.7 percent between 2022 and 2023 and the dollars lent fell
43.4 percent, so the average loan shrank at the same time as the count. By 2025
the market had recovered to 78.7 percent of its 2022 application volume, 75.6
percent of its originations and 72.6 percent of its dollars.

**The incompleteness rate rises in every year, 4.32 to 5.53, while the count of
incomplete applications barely moves**, from 21,618 to 21,791. The rate rose
because the denominator shrank, not because more applications went incomplete.
That is the clearest case on this page for printing a count beside every rate,
and it is the reason every table here does.

The withdrawal rate moves very little across the four years, which makes the
incompleteness drift easier to see rather than harder.

### B2. The Typical Loan That Was Made, by Year

| activity_year | originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|---|
| 2,022 | 307,252 | 119,000 | 465,000 | 255,000 | 75.00 | 2.16 | 4.375 |
| 2,023 | 203,072 | 124,000 | 445,000 | 215,000 | 75.39 | 1.87 | 6.750 |
| 2,024 | 208,814 | 130,000 | 475,000 | 235,000 | 75.00 | 1.88 | 6.875 |
| 2,025 | 232,233 | 137,000 | 525,000 | 255,000 | 74.72 | 1.87 | 6.625 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=B2">Query B2</a></summary>

```sql
SELECT activity_year,
       count(*)                                                        AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                        AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY property_value)
             AS DECIMAL(24,8)))                                        AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_amount)
             AS DECIMAL(24,8)))                                        AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                     AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN income_thousands > 0
                            THEN loan_amount / (income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                     AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY interest_rate)
             AS DECIMAL(24,8)), 3)                                     AS median_interest_rate
FROM marts.fct_application
WHERE action_taken = '1'
GROUP BY 1
ORDER BY 1;
```

</details>

**The median interest rate moved 237.5 basis points in one year**, from 4.375
percent in 2022 to 6.750 in 2023. Every pooled median rate elsewhere on this page
is an average across that move, and is read with this table beside it.

Median applicant income rose from 119,000 dollars to 137,000 across the four
years while the median loan fell from 255,000 to 215,000 and then recovered to
255,000. Because income rose while borrowing did not, **loan-to-income fell from
2.16 to 1.87 in 2023 and stayed there**: borrowers did not return to 2022 leverage
even when loan sizes did.

Median loan-to-value is flat near 75 throughout. It is the one measure in this
table the rate shock did not move, which is consistent with it being set by
product rules rather than by what a borrower can afford.

</details>

---

## C. Applicant Demographics: Affordability and Borrowing

<details>
<summary><b>Eleven queries: the borrowing profile of each applicant group, and the market by income band</b></summary>

Two subsections. **Borrowing profile by applicant group** is C1a to C3b, three
pairs: race, sex and age, each split into a volume-and-outcomes query and a
characteristics query. **Income segmentation** is C4a to C7, the same pair
applied to income bands, then each applicant group placed across those bands.

The pairs exist because a single table of fifteen columns is a spreadsheet with a
horizontal scrollbar, and because the two halves cover different populations:
outcomes cover every application, characteristics cover only the loans that
completed.

**Two conventions specific to this section.** Loan-to-value is the ratio as the
lender filed it, which counts every lien on the property rather than only the
loan in the row; A2 sets out the test for that. And median applicant income
excludes rows reporting zero or a negative figure everywhere, which is the same
treatment loan-to-income has to use.

### C1a. Applications and Outcomes by Applicant Race

**The pair.** The **a** query covers every application the group filed, on A1's
denominators, and its four rates sum to 100 across the row. The **b** query
covers only the loans that completed, for the coverage reason in
[A2](#a2-the-typical-loan-that-was-made). `originated_loans` appears in both: in
the first it is the funnel result, in the second it is the denominator standing
behind six medians.

| applicant_race | total_applications | approval_rate | denial_rate | incomplete_rate | withdrawal_rate | originated_loans | originated_share_pct | total_loan_amount |
|---|---|---|---|---|---|---|---|---|
| White | 983,251 | 66.21 | 18.49 | 4.36 | 10.94 | 621,461 | 65.32 | 198,233,035,000 |
| Race Not Available | 299,190 | 57.94 | 21.22 | 5.91 | 14.93 | 161,122 | 16.94 | 98,886,290,000 |
| Asian | 147,339 | 62.33 | 18.55 | 5.78 | 13.34 | 87,024 | 9.15 | 44,128,540,000 |
| Black or African American | 124,980 | 50.04 | 30.82 | 5.74 | 13.40 | 58,130 | 6.11 | 19,625,495,000 |
| Joint | 27,293 | 68.37 | 14.95 | 3.92 | 12.75 | 17,886 | 1.88 | 8,857,590,000 |
| American Indian or Alaska Native | 6,829 | 42.20 | 36.45 | 9.06 | 12.29 | 2,695 | 0.28 | 673,495,000 |
| 2 or more minority races | 3,821 | 42.14 | 37.16 | 8.43 | 12.27 | 1,502 | 0.16 | 548,080,000 |
| Native Hawaiian or Other Pacific Islander | 3,336 | 44.18 | 38.07 | 5.58 | 12.17 | 1,364 | 0.14 | 411,115,000 |
| Free Form Text Only | 637 | 30.61 | 51.33 | 7.38 | 10.68 | 187 | 0.02 | 54,100,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C1a">Query C1a</a></summary>

```sql
SELECT a.derived_race                                                            AS applicant_race,
       count(*)                                                             AS total_applications,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS incomplete_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS withdrawal_rate,
       count(*) FILTER (WHERE f.action_taken = '1')                         AS originated_loans,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                            AS originated_share_pct,
       sum(f.loan_amount) FILTER (WHERE f.action_taken = '1')               AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

White applicants account for 65.32 percent of originated loans and Race Not
Available for a further 16.94, so the six named minority categories together
account for 17.74 percent.

Approval ranges from 68.37 percent to 30.61 across the nine categories, and the
four rates behave differently from one another. **Withdrawal sits in a narrow
band of 10.68 to 14.93 for every category and incompleteness in a band of 3.92 to
9.06, so approval and denial carry nearly all of the variation.**

Free Form Text Only carries 637 applications, 0.02 percent of originations. Its
rates move on numbers too small to be stable and it is shown for completeness
rather than comparison.

### C1b. Loan Characteristics by Applicant Race

| applicant_race | originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|---|
| White | 621,461 | 122,000 | 405,000 | 205,000 | 75.00 | 1.79 | 6.375 |
| Race Not Available | 161,122 | 139,000 | 585,000 | 325,000 | 75.00 | 2.12 | 6.375 |
| Asian | 87,024 | 146,000 | 725,000 | 455,000 | 70.55 | 2.92 | 6.250 |
| Black or African American | 58,130 | 115,000 | 525,000 | 255,000 | 80.00 | 2.54 | 6.375 |
| Joint | 17,886 | 179,000 | 595,000 | 355,000 | 80.00 | 2.00 | 6.125 |
| American Indian or Alaska Native | 2,695 | 92,000 | 345,000 | 165,000 | 79.46 | 2.02 | 6.490 |
| 2 or more minority races | 1,502 | 120,000 | 545,000 | 265,000 | 80.00 | 2.77 | 6.375 |
| Native Hawaiian or Other Pacific Islander | 1,364 | 107,000 | 495,000 | 195,000 | 76.44 | 2.03 | 6.375 |
| Free Form Text Only | 187 | 116,000 | 575,000 | 205,000 | 74.07 | 2.02 | 6.250 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C1b">Query C1b</a></summary>

```sql
SELECT a.derived_race                                                            AS applicant_race,
       count(*)                                                             AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                                  AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                                  AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                                  AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                               AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                               AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS DECIMAL(24,8)), 3)                                               AS median_interest_rate
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1'
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

**The property and income columns do not follow the volume column.** White
applicants record the lowest median property value of any named group except
American Indian or Alaska Native, at 405,000 dollars against 725,000 for Asian
applicants and 525,000 for Black applicants, and the lowest median loan-to-income
at 1.79. Asian applicants record the highest of both, with a loan-to-income of
2.92 that is 1.6 times the White figure.

**A large part of that is geography rather than anything about applicants.**
These groups are not evenly spread across the state, and
[A7](#a7-the-ten-most-expensive-counties) established that median property value
runs from 1,355,000 dollars in Manhattan down to a fraction of that upstate. A
group concentrated in New York City records a high median property value and a
high loan-to-income whatever else is true of it. Any reading of those two columns
that does not hold location constant is reading the map.

Leverage clusters between 70.55 and 80 for every category including the
unreported ones, and price is tighter still: 6.125 to 6.490 percent, a spread of
36.5 basis points across groups whose median property values differ by a factor
of two. **Whatever separates these groups, the rate on the note separates them
far less than anything else measured here.**

### C2a. Applications and Outcomes by Applicant Sex

**The pair.** The **a** query covers every application the group filed, on A1's
denominators, and its four rates sum to 100 across the row. The **b** query
covers only the loans that completed, for the coverage reason in
[A2](#a2-the-typical-loan-that-was-made). `originated_loans` appears in both: in
the first it is the funnel result, in the second it is the denominator standing
behind six medians.

| applicant_sex | total_applications | approval_rate | denial_rate | incomplete_rate | withdrawal_rate | originated_loans | originated_share_pct | total_loan_amount |
|---|---|---|---|---|---|---|---|---|
| Male | 557,903 | 59.21 | 22.71 | 5.71 | 12.37 | 312,145 | 32.81 | 111,931,545,000 |
| Joint | 505,023 | 69.80 | 15.14 | 3.95 | 11.11 | 338,370 | 35.57 | 130,909,075,000 |
| Female | 371,627 | 59.93 | 23.31 | 4.96 | 11.80 | 210,493 | 22.13 | 59,604,675,000 |
| Sex Not Available | 162,123 | 60.42 | 19.12 | 5.11 | 15.35 | 90,363 | 9.50 | 68,972,445,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C2a">Query C2a</a></summary>

```sql
SELECT a.derived_sex                                                            AS applicant_sex,
       count(*)                                                             AS total_applications,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS incomplete_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS withdrawal_rate,
       count(*) FILTER (WHERE f.action_taken = '1')                         AS originated_loans,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                            AS originated_share_pct,
       sum(f.loan_amount) FILTER (WHERE f.action_taken = '1')               AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

Male applicants file the most applications at 557,903, but Joint produces the
most loans at 338,370, because Joint converts far better.

**Male and female applicants record approval within 0.72 of a point of each
other**, 59.21 against 59.93, and denial within 0.60, 22.71 against 23.31. On the
two headline outcome measures they are close to indistinguishable.

Joint records the highest approval rate at 69.80, which is 10.6 points above male
and 9.9 above female. Two incomes and two credit records make a stronger
application than one, and Joint is a category of application rather than a
category of person.

### C2b. Loan Characteristics by Applicant Sex

| applicant_sex | originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|---|
| Joint | 338,370 | 156,000 | 525,000 | 265,000 | 75.74 | 1.80 | 6.250 |
| Male | 312,145 | 115,000 | 455,000 | 225,000 | 75.00 | 2.02 | 6.375 |
| Female | 210,493 | 95,000 | 375,000 | 195,000 | 75.00 | 2.19 | 6.250 |
| Sex Not Available | 90,363 | 139,000 | 615,000 | 335,000 | 70.00 | 1.91 | 6.375 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C2b">Query C2b</a></summary>

```sql
SELECT a.derived_sex                                                            AS applicant_sex,
       count(*)                                                             AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                                 AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                                 AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                                 AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                              AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                              AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS DECIMAL(24,8)), 3)                                              AS median_interest_rate
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1'
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

Median applicant income is 115,000 dollars for male applicants and 95,000 for
female, a ratio of 1.21. Median property value is 455,000 against 375,000 and
median loan 225,000 against 195,000, ratios of 1.21 and 1.15. **Because income
and loan size move by nearly the same factor, loan-to-income differs by much
less**, 2.02 against 2.19, and the median interest rate is 12.5 basis points
lower for female applicants than for male.

Sex Not Available does not behave like the three named categories: highest median
property value at 615,000, highest median loan at 335,000, lowest loan-to-value
at 70. Taken with its withdrawal rate in C2a, that is disproportionately
companies, trusts and estates, which have no sex to report. The same signature
appears in the age pair below, far more strongly.

### C3a. Applications and Outcomes by Applicant Age Band

**The pair.** The **a** query covers every application the group filed, on A1's
denominators, and its four rates sum to 100 across the row. The **b** query
covers only the loans that completed, for the coverage reason in
[A2](#a2-the-typical-loan-that-was-made). `originated_loans` appears in both: in
the first it is the funnel result, in the second it is the denominator standing
behind six medians.

| applicant_age | total_applications | approval_rate | denial_rate | incomplete_rate | withdrawal_rate | originated_loans | originated_share_pct | total_loan_amount |
|---|---|---|---|---|---|---|---|---|
| 35-44 | 396,860 | 64.56 | 18.79 | 4.67 | 11.98 | 243,375 | 25.58 | 103,034,665,000 |
| 45-54 | 338,638 | 60.86 | 22.46 | 5.24 | 11.43 | 195,629 | 20.56 | 70,794,770,000 |
| 25-34 | 299,818 | 69.53 | 14.56 | 3.92 | 11.98 | 198,254 | 20.84 | 75,393,700,000 |
| 55-64 | 272,665 | 58.51 | 23.95 | 5.61 | 11.93 | 150,629 | 15.83 | 44,641,795,000 |
| 65-74 | 141,773 | 57.55 | 23.80 | 5.66 | 12.99 | 76,991 | 8.09 | 19,081,335,000 |
| 8888 | 57,804 | 66.87 | 13.33 | 4.14 | 15.66 | 36,724 | 3.86 | 45,707,010,000 |
| >74 | 53,736 | 52.83 | 26.11 | 6.65 | 14.41 | 26,457 | 2.78 | 6,412,225,000 |
| <25 | 35,382 | 69.48 | 16.15 | 3.29 | 11.07 | 23,312 | 2.45 | 6,352,240,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C3a">Query C3a</a></summary>

```sql
SELECT a.applicant_age                                                            AS applicant_age,
       count(*)                                                             AS total_applications,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS incomplete_rate,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS withdrawal_rate,
       count(*) FILTER (WHERE f.action_taken = '1')                         AS originated_loans,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                            AS originated_share_pct,
       sum(f.loan_amount) FILTER (WHERE f.action_taken = '1')               AS total_loan_amount
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

**Approval falls steadily with age across the named bands**, from 69.53 percent
at 25 to 34 down to 52.83 above 74, a spread of 16.7 points. Applicants under 25
sit at 69.48, level with the 25 to 34 band, so the pattern is a decline with age
rather than a disadvantage at both ends.

The 8888 band, HMDA's code for an age that was not provided, records the second
highest approval rate in the table at 66.87 and the highest withdrawal rate at
15.66.

### C3b. Loan Characteristics by Applicant Age Band

| applicant_age | originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|---|
| 35-44 | 243,375 | 145,000 | 525,000 | 295,000 | 79.78 | 2.07 | 6.250 |
| 25-34 | 198,254 | 122,000 | 405,000 | 285,000 | 80.00 | 2.50 | 6.250 |
| 45-54 | 195,629 | 142,000 | 525,000 | 225,000 | 72.09 | 1.59 | 6.375 |
| 55-64 | 150,629 | 122,000 | 465,000 | 185,000 | 63.64 | 1.46 | 6.290 |
| 65-74 | 76,991 | 95,000 | 405,000 | 155,000 | 55.13 | 1.60 | 6.375 |
| 8888 | 36,724 | 101,000 | 1,005,000 | 565,000 | 66.05 | 0.97 | 6.924 |
| >74 | 26,457 | 76,000 | 415,000 | 145,000 | 48.14 | 1.79 | 6.490 |
| <25 | 23,312 | 77,000 | 225,000 | 195,000 | 90.00 | 2.65 | 6.375 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C3b">Query C3b</a></summary>

```sql
SELECT a.applicant_age                                                            AS applicant_age,
       count(*)                                                             AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                                   AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.property_value)
             AS DECIMAL(24,8)))                                                   AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_amount)
             AS DECIMAL(24,8)))                                                   AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                                AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                                AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS DECIMAL(24,8)), 3)                                                AS median_interest_rate
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken = '1'
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

*For the 8888 band, median applicant income and median loan-to-income rest on the
111 loans of 36,724 that report an income. Neither figure should be read as that
band's income.*

**The cleanest pattern in the project is the loan-to-value column.** It falls at
every single step of age: 90 under 25, then 80, 79.78, 72.09, 63.64, 55.13 and
48.14 above 74. Seven bands, seven steps, no reversals, a range of nearly 42
points. The youngest borrowers finance nine tenths of the property and the oldest
finance under half. The ladder survives being measured inside 2025 alone, where
it reads 90, 80, 77.73, 70, 61.36, 53.56, 46.32.

**The 8888 band is not a band of people who left a box blank, and three figures
say so.** It reports no usable income on 99.7 percent of its loans, against 2.9
to 5.1 percent for every named band. Its median property value is 1,005,000
dollars and its median loan 565,000, both roughly double the highest named band.
Its median interest rate is 6.924 percent, between 55 and 67 basis points above
every other band, and measured within 2025 alone it sits at 7.18 against 6.50 to
6.625, so the premium holds inside a single rate environment.

The scale is worth stating. The band is 3.86 percent of originated loans and
12.31 percent of all dollars disbursed, a concentration ratio of 3.2. No named
band comes close. Removing it would quietly drop an eighth of the money in this
market, which is why it is kept.

### C4a. Applications and Outcomes by Applicant Income Band

| income_band | total_applications | approval_rate | denial_rate | incomplete_rate | withdrawal_rate | originated_loans | originated_share_pct | total_loan_amount |
|---|---|---|---|---|---|---|---|---|
| Under 50k | 141,619 | 46.65 | 38.40 | 4.35 | 10.61 | 61,669 | 6.48 | 7,928,360,000 |
| 50k to 74k | 212,200 | 59.35 | 25.26 | 4.47 | 10.92 | 118,761 | 12.48 | 17,700,235,000 |
| 75k to 99k | 216,270 | 62.50 | 21.66 | 4.75 | 11.09 | 127,952 | 13.45 | 25,412,990,000 |
| 100k to 149k | 349,698 | 65.58 | 18.11 | 4.83 | 11.48 | 217,903 | 22.90 | 60,475,845,000 |
| 150k to 199k | 204,876 | 67.60 | 15.63 | 4.93 | 11.84 | 131,972 | 13.87 | 47,038,230,000 |
| 200k to 299k | 173,055 | 67.62 | 14.39 | 5.27 | 12.72 | 111,616 | 11.73 | 48,975,375,000 |
| 300k and over | 166,530 | 65.84 | 12.78 | 6.01 | 15.37 | 104,533 | 10.99 | 96,783,845,000 |
| Income not reported | 132,428 | 61.83 | 18.43 | 4.89 | 14.86 | 76,965 | 8.09 | 67,102,860,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C4a">Query C4a</a></summary>

```sql
WITH application AS (
    SELECT f.action_taken,
           f.loan_amount,
           f.income_thousands,
           f.property_value,
           f.interest_rate,
           f.loan_to_value_ratio,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                WHEN f.income_thousands <  50 THEN 1
                WHEN f.income_thousands <  75 THEN 2
                WHEN f.income_thousands < 100 THEN 3
                WHEN f.income_thousands < 150 THEN 4
                WHEN f.income_thousands < 200 THEN 5
                WHEN f.income_thousands < 300 THEN 6
                ELSE 7
           END AS band_key
    FROM marts.fct_application f
    WHERE f.action_taken <> '6'
),
band_label (band_key, income_band) AS (
    VALUES (1, 'Under 50k'),    (2, '50k to 74k'),   (3, '75k to 99k'),
           (4, '100k to 149k'), (5, '150k to 199k'), (6, '200k to 299k'),
           (7, '300k and over'), (8, 'Income not reported')
)
SELECT l.income_band,
       count(*)                                                                   AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS denial_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS incomplete_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                                AS withdrawal_rate,
       count(*) FILTER (WHERE a.action_taken = '1')                               AS originated_loans,
       round(CAST(100.0 * count(*) FILTER (WHERE a.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE a.action_taken = '1')) OVER () AS DECIMAL(24,8)), 2)
                                                                                  AS originated_share_pct,
       sum(a.loan_amount) FILTER (WHERE a.action_taken = '1')                     AS total_loan_amount
FROM application a
JOIN band_label l ON l.band_key = a.band_key
GROUP BY a.band_key, l.income_band
ORDER BY a.band_key;
```

</details>

There is no income band in the model: HMDA files a single number. The bands are
built in the query, defined once in a CTE and joined to a labels table so the SQL
carries one `CASE` rather than two and the rows come back in income order rather
than alphabetical order. The cut points are round numbers placed on the actual
distribution, whose quartiles are 76,000 and 190,000 dollars and whose median is
120,000.

**Denial falls at every step of income.** 38.40 percent under 50,000 dollars,
then 25.26, 21.66, 18.11, 15.63, 14.39 and 12.78 above 300,000. Seven bands,
seven steps, no reversals, a range of 25.6 points.

**Approval does not.** It climbs from 46.65 to 67.60, flattens, then falls back to
65.84 in the top band while denial is still falling. Incompleteness and
withdrawal are what overtake it, and they cross denial exactly where approval
stops climbing: at 100,000 to 149,000 denial is 18.11 against 16.31 combined; at
150,000 to 199,000 it is 15.63 against 16.77. **Below that crossing what ends an
application is usually the lender's decision; above it, usually the applicant's.**

The money is distributed far more unevenly than the loans. The top band takes 26.1
percent of the dollars from 11.0 percent of the loans; the bottom band takes 2.1
percent from 6.5 percent.

### C4b. Loan Characteristics by Applicant Income Band

| income_band | originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|---|
| Under 50k | 61,669 | 40,000 | 175,000 | 105,000 | 70.22 | 2.64 | 6.250 |
| 50k to 74k | 118,761 | 63,000 | 225,000 | 135,000 | 77.00 | 2.25 | 6.250 |
| 75k to 99k | 127,952 | 87,000 | 305,000 | 175,000 | 75.68 | 2.08 | 6.250 |
| 100k to 149k | 217,903 | 122,000 | 445,000 | 245,000 | 77.57 | 2.03 | 6.250 |
| 150k to 199k | 131,972 | 170,000 | 595,000 | 325,000 | 77.98 | 1.92 | 6.375 |
| 200k to 299k | 111,616 | 235,000 | 725,000 | 405,000 | 75.00 | 1.71 | 6.375 |
| 300k and over | 104,533 | 450,000 | 1,255,000 | 705,000 | 74.99 | 1.38 | 6.000 |
| Income not reported | 76,965 |  | 765,000 | 455,000 | 68.05 |  | 6.750 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C4b">Query C4b</a></summary>

```sql
WITH application AS (
    SELECT f.action_taken,
           f.loan_amount,
           f.income_thousands,
           f.property_value,
           f.interest_rate,
           f.loan_to_value_ratio,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                WHEN f.income_thousands <  50 THEN 1
                WHEN f.income_thousands <  75 THEN 2
                WHEN f.income_thousands < 100 THEN 3
                WHEN f.income_thousands < 150 THEN 4
                WHEN f.income_thousands < 200 THEN 5
                WHEN f.income_thousands < 300 THEN 6
                ELSE 7
           END AS band_key
    FROM marts.fct_application f
    WHERE f.action_taken <> '6'
),
band_label (band_key, income_band) AS (
    VALUES (1, 'Under 50k'),    (2, '50k to 74k'),   (3, '75k to 99k'),
           (4, '100k to 149k'), (5, '150k to 199k'), (6, '200k to 299k'),
           (7, '300k and over'), (8, 'Income not reported')
)
SELECT l.income_band,
       count(*)                                                             AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN a.income_thousands > 0
                            THEN a.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                             AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.property_value)
             AS DECIMAL(24,8)))                                             AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.loan_amount)
             AS DECIMAL(24,8)))                                             AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.loan_to_value_ratio)
             AS DECIMAL(24,8)), 2)                                          AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN a.income_thousands > 0
                            THEN a.loan_amount / (a.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                          AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY a.interest_rate)
             AS DECIMAL(24,8)), 3)                                          AS median_interest_rate
FROM application a
JOIN band_label l ON l.band_key = a.band_key
WHERE a.action_taken = '1'
GROUP BY a.band_key, l.income_band
ORDER BY a.band_key;
```

</details>

Income rises 11.3 times across the seven named bands, property value 7.2 times
and loan amount 6.7 times. Because borrowing grows more slowly than income,
**loan-to-income falls at every step**, from 2.64 to 1.38. That is the arithmetic
behind the denial ladder in C4a.

**Leverage does not follow income.** Loan-to-value reads 70.22, 77.00, 75.68,
77.57, 77.98, 75.00, 74.99, close to flat with the lowest value at the bottom of
the table rather than the top. The purpose mix explains it: home purchase is
46.02 percent of originations in the bottom band against 53.31 across the market,
while refinancing is 14.28 against 11.29 and other purpose 11.82 against 9.35. A
refinance or an improvement loan is small against the house it sits on. **The
band is not putting more equity down, it is doing less buying.**

For Income not reported, median applicant income and median loan-to-income are
blank rather than zero. Every row in that band reports no usable income, so there
is nothing to take a median of, and a zero would invite being read as an income.

### C5. Income Band by Applicant Race

Each row is an applicant group, each column an income band, and the cells are
that group's applications as a percentage of its own row, so **every row sums to
100**. Counted on applications rather than originations, so the row totals tie
exactly to the `total_applications` column in C1a, C2a and C3a.

| applicant_race | total_applications | pct_under_50k | pct_50k_to_74k | pct_75k_to_99k | pct_100k_to_149k | pct_150k_to_199k | pct_200k_to_299k | pct_300k_and_over | pct_not_reported |
|---|---|---|---|---|---|---|---|---|---|
| White | 983,251 | 10.04 | 14.94 | 14.54 | 22.24 | 12.83 | 10.96 | 10.76 | 3.70 |
| Race Not Available | 299,190 | 5.95 | 9.57 | 10.61 | 18.44 | 11.26 | 9.68 | 10.15 | 24.34 |
| Asian | 147,339 | 5.63 | 8.61 | 11.33 | 22.69 | 14.96 | 13.48 | 12.70 | 10.60 |
| Black or African American | 124,980 | 11.19 | 15.64 | 15.96 | 26.69 | 13.48 | 8.26 | 3.83 | 4.96 |
| Joint | 27,293 | 2.34 | 6.05 | 9.22 | 21.17 | 17.00 | 18.74 | 22.60 | 2.88 |
| American Indian or Alaska Native | 6,829 | 16.99 | 21.34 | 17.28 | 19.34 | 9.58 | 6.49 | 5.26 | 3.73 |
| 2 or more minority races | 3,821 | 12.85 | 16.04 | 15.34 | 25.67 | 12.14 | 8.56 | 5.21 | 4.19 |
| Native Hawaiian or Other Pacific Islander | 3,336 | 13.64 | 18.82 | 15.68 | 25.78 | 10.46 | 5.91 | 4.41 | 5.31 |
| Free Form Text Only | 637 | 13.81 | 16.64 | 15.86 | 22.61 | 11.46 | 8.32 | 5.02 | 6.28 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C5">Query C5</a></summary>

```sql
WITH banded AS (
    SELECT a.derived_race         AS applicant_race,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                WHEN f.income_thousands <  50 THEN 1
                WHEN f.income_thousands <  75 THEN 2
                WHEN f.income_thousands < 100 THEN 3
                WHEN f.income_thousands < 150 THEN 4
                WHEN f.income_thousands < 200 THEN 5
                WHEN f.income_thousands < 300 THEN 6
                ELSE 7
           END AS band_key
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
)
SELECT b.applicant_race,
       count(*)                                                   AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 1) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)             AS pct_under_50k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 2) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_50k_to_74k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 3) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_75k_to_99k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 4) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_100k_to_149k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 5) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_150k_to_199k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 6) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_200k_to_299k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 7) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)         AS pct_300k_and_over,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 8) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_not_reported
FROM banded b
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

**Joint is the most top-heavy row and American Indian or Alaska Native the most
bottom-heavy.** Joint puts 41.34 percent of its applications above 200,000
dollars and 8.39 percent below 75,000; American Indian or Alaska Native reverses
it at 11.75 and 38.33.

White and Black applicants have more similar distributions than the headline
medians suggest, and they diverge in one place. Below 150,000 dollars they run
61.76 and 69.48 percent, and the 26.69 percent of Black applications at 100,000
to 149,000 is the largest single cell in the table. The difference is at the top:
21.72 percent of White applications sit above 200,000 against 12.09 percent.

**Race Not Available does not report income either.** 24.34 percent of that row
falls in the not-reported band against 3.70 for White. Whatever causes one field
to be left blank tends to leave the other blank too, which is worth knowing
before that category is read as a group of people.

### C6. Income Band by Applicant Sex

Each row is an applicant group, each column an income band, and the cells are
that group's applications as a percentage of its own row, so **every row sums to
100**. Counted on applications rather than originations, so the row totals tie
exactly to the `total_applications` column in C1a, C2a and C3a.

| applicant_sex | total_applications | pct_under_50k | pct_50k_to_74k | pct_75k_to_99k | pct_100k_to_149k | pct_150k_to_199k | pct_200k_to_299k | pct_300k_and_over | pct_not_reported |
|---|---|---|---|---|---|---|---|---|---|
| Male | 557,903 | 10.16 | 15.82 | 14.90 | 21.34 | 11.37 | 9.17 | 11.08 | 6.16 |
| Joint | 505,023 | 3.09 | 7.38 | 11.26 | 25.44 | 18.54 | 17.16 | 14.42 | 2.71 |
| Female | 371,627 | 16.36 | 19.84 | 16.92 | 21.44 | 9.18 | 6.20 | 4.72 | 5.34 |
| Sex Not Available | 162,123 | 5.28 | 7.97 | 8.24 | 13.85 | 8.44 | 7.54 | 8.86 | 39.82 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C6">Query C6</a></summary>

```sql
WITH banded AS (
    SELECT a.derived_sex          AS applicant_sex,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                WHEN f.income_thousands <  50 THEN 1
                WHEN f.income_thousands <  75 THEN 2
                WHEN f.income_thousands < 100 THEN 3
                WHEN f.income_thousands < 150 THEN 4
                WHEN f.income_thousands < 200 THEN 5
                WHEN f.income_thousands < 300 THEN 6
                ELSE 7
           END AS band_key
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
)
SELECT b.applicant_sex,
       count(*)                                                   AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 1) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)             AS pct_under_50k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 2) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_50k_to_74k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 3) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_75k_to_99k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 4) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_100k_to_149k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 5) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_150k_to_199k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 6) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_200k_to_299k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 7) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)         AS pct_300k_and_over,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 8) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_not_reported
FROM banded b
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

**The two named individual categories are nearly identical in the middle and
diverge at both ends.** At 100,000 to 149,000 dollars male applications are 21.34
percent of their row and female 21.44, a tenth of a point apart. Below 75,000 the
figures are 25.98 and 36.20. Above 200,000 they are 20.25 and 10.92. The
distributions cross almost exactly at the middle band and separate symmetrically
either side of it.

Joint is top-heavy again, 31.58 percent above 200,000 against 10.47 below 75,000,
and at 505,023 applications it is the second largest row. Any market-level income
figure is partly measuring how many applications are joint.

**Sex Not Available leaves income blank on 39.82 percent of its applications**,
six to seven times the rate of the three named categories, which is the same
signature as C2b and as the 8888 age band.

### C7. Income Band by Applicant Age Band

Each row is an applicant group, each column an income band, and the cells are
that group's applications as a percentage of its own row, so **every row sums to
100**. Counted on applications rather than originations, so the row totals tie
exactly to the `total_applications` column in C1a, C2a and C3a.

| applicant_age | total_applications | pct_under_50k | pct_50k_to_74k | pct_75k_to_99k | pct_100k_to_149k | pct_150k_to_199k | pct_200k_to_299k | pct_300k_and_over | pct_not_reported |
|---|---|---|---|---|---|---|---|---|---|
| 35-44 | 396,860 | 5.43 | 10.47 | 12.22 | 23.02 | 15.00 | 13.82 | 14.59 | 5.44 |
| 45-54 | 338,638 | 6.32 | 11.04 | 12.94 | 23.63 | 14.68 | 12.94 | 13.04 | 5.41 |
| 25-34 | 299,818 | 7.29 | 14.78 | 15.01 | 24.29 | 14.40 | 11.31 | 8.36 | 4.56 |
| 55-64 | 272,665 | 10.54 | 14.58 | 14.99 | 22.99 | 12.51 | 10.03 | 9.74 | 4.63 |
| 65-74 | 141,773 | 18.41 | 19.58 | 16.72 | 20.00 | 8.94 | 6.54 | 6.33 | 3.49 |
| 8888 | 57,804 | 0.16 | 0.13 | 0.10 | 0.15 | 0.06 | 0.06 | 0.05 | 99.29 |
| >74 | 53,736 | 27.58 | 22.32 | 15.49 | 15.05 | 6.26 | 4.65 | 4.63 | 4.01 |
| <25 | 35,382 | 19.94 | 26.51 | 16.95 | 17.77 | 6.45 | 3.69 | 3.86 | 4.83 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=C7">Query C7</a></summary>

```sql
WITH banded AS (
    SELECT a.applicant_age        AS applicant_age,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                WHEN f.income_thousands <  50 THEN 1
                WHEN f.income_thousands <  75 THEN 2
                WHEN f.income_thousands < 100 THEN 3
                WHEN f.income_thousands < 150 THEN 4
                WHEN f.income_thousands < 200 THEN 5
                WHEN f.income_thousands < 300 THEN 6
                ELSE 7
           END AS band_key
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
)
SELECT b.applicant_age,
       count(*)                                                   AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 1) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)             AS pct_under_50k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 2) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_50k_to_74k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 3) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)            AS pct_75k_to_99k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 4) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_100k_to_149k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 5) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_150k_to_199k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 6) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_200k_to_299k,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 7) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)         AS pct_300k_and_over,
       round(CAST(100.0 * count(*) FILTER (WHERE b.band_key = 8) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)          AS pct_not_reported
FROM banded b
GROUP BY 1
ORDER BY 2 DESC;
```

</details>

**The named bands form a U.** Both ends of the age range sit low in the income
distribution and the middle sits high. Under 25, 46.45 percent of applications
fall below 75,000 dollars; above 74, 49.90 percent do. In between, the 35 to 44
and 45 to 54 bands put 28.41 and 25.98 percent above 200,000.

That U is the plainest explanation available for the approval ladder in C3a and
the leverage ladder in C3b. The oldest band is the poorest on reported income and
borrows least against the most equity; the youngest is nearly as poor and borrows
most against the least.

**The 8888 band reports no income on 99.29 percent of its applications**, with the
remaining seven cells holding between 0.05 and 0.16 percent each. This is the
cleanest evidence on this page that the band is not a group of people who left
the age box blank, and it is the figure to quote rather than that band's median
income.

</details>

---

## D. Mortgage Denial Analysis

<details>
<summary><b>Six queries: how often each reason is cited, per 100 applications, by income band, loan type, loan purpose, race, sex and age band</b></summary>

Rows are denial reasons, columns are the grouping, and **each cell is the number
of times that reason was cited for that group per 100 applications the group
filed.** The last row of each table is the column total, which is that group's
whole denial-reason rate.

**Why a rate and not a share.** The first version of these tables divided by the
reason's own total, so a cell read "this group's share of all debt-to-income
denials". Ranking the nine race categories by that figure gives a Spearman
correlation of **+0.967 with application volume** and **−0.767 with denial
rate**: it was a ranking of who filed the most applications, pointing the wrong
way on denial. White applications showed 57.31 percent of all debt-to-income
denials, the largest figure in the row, while having the second lowest denial
rate of the nine. Dividing by each group's own applications removes that
entirely, and the same figure becomes 7.88 against 13.43 for Black and 20.77 for
Native Hawaiian.

**The denominator is the one A1 uses for the denial rate**, which buys a
reconciliation: the bottom row of every table equals that group's denial rate
multiplied by its reasons per denial, with no residual. This section therefore
cannot disagree with A, C or F.

**The unit is a reason citation, not an application.** HMDA lets a lender cite up
to four reasons on one denial, so the 320,762 denied applications carry 411,362
citations, 1.2825 each. One application can appear in two rows, which is why the
columns do not sum to 100 and are not meant to. No application cites the same
reason twice.

**The denied population is action code 3 or 7, as in A1.** That filter is not
cosmetic: the bridge table also carries reasons against 21,665 applications that
ended as originated loans, plus smaller numbers on withdrawn and incomplete
ones, which are filer errors. Counting them would put a denial reason against a
closed loan.

Three reasons carry 72 percent of all denials: debt-to-income at 32.87 percent,
credit history at 21.71 and collateral at 17.45. Mortgage insurance denied has
515 citations and its row is shown for completeness rather than read as a
pattern.

### D1. Denial Reason by Applicant Income Band

*Every cell is the number of times this reason was cited per 100 applications
the column group filed, purchased loans excluded. It is a rate, not a share of
the column: a column sums to that group's denial rate times its reasons per
denial, and the bottom row prints that total.*

| denial_reason | reason_occurrences | inc_under_50k | inc_50k_to_74k | inc_75k_to_99k | inc_100k_to_149k | inc_150k_to_199k | inc_200k_to_299k | inc_300k_and_over | inc_not_reported |
|---|---|---|---|---|---|---|---|---|---|
| Debt-to-income ratio | 135,207 | 23.44 | 12.55 | 9.81 | 7.46 | 5.35 | 4.05 | 2.41 | 4.61 |
| Credit history | 89,302 | 10.79 | 7.34 | 6.09 | 5.14 | 4.55 | 4.11 | 2.80 | 4.69 |
| Collateral | 71,778 | 5.10 | 4.83 | 4.75 | 4.43 | 4.35 | 4.43 | 4.78 | 3.03 |
| Other | 49,153 | 4.87 | 3.49 | 3.17 | 2.69 | 2.42 | 2.44 | 2.69 | 3.73 |
| Credit application incomplete | 24,663 | 1.76 | 1.58 | 1.60 | 1.48 | 1.41 | 1.39 | 1.26 | 2.10 |
| Unverifiable information | 16,800 | 1.41 | 0.92 | 0.89 | 0.88 | 0.95 | 0.98 | 1.24 | 1.64 |
| Insufficient cash (downpayment, closing costs) | 12,915 | 1.47 | 1.06 | 0.81 | 0.67 | 0.60 | 0.58 | 0.75 | 0.74 |
| Employment history | 6,437 | 1.23 | 0.52 | 0.36 | 0.26 | 0.20 | 0.16 | 0.17 | 0.69 |
| Exempt (partially exempt filer) | 4,592 | 0.67 | 0.34 | 0.27 | 0.19 | 0.13 | 0.12 | 0.11 | 0.75 |
| Mortgage insurance denied | 515 | 0.09 | 0.05 | 0.04 | 0.03 | 0.02 | 0.01 | 0.01 | 0.02 |
| All reasons | 411,362 | 50.82 | 32.67 | 27.78 | 23.23 | 19.97 | 18.29 | 16.22 | 22.01 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=D1">Query D1</a></summary>

```sql
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 1) AS apps_inc_under_50k,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 2) AS apps_inc_50k_to_74k,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 3) AS apps_inc_75k_to_99k,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 4) AS apps_inc_100k_to_149k,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 5) AS apps_inc_150k_to_199k,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 6) AS apps_inc_200k_to_299k,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 7) AS apps_inc_300k_and_over,
           count(*) FILTER (WHERE CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END = 8) AS apps_inc_not_reported
    FROM marts.fct_application f
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0 THEN 8
                     WHEN f.income_thousands <  50 THEN 1
                     WHEN f.income_thousands <  75 THEN 2
                     WHEN f.income_thousands < 100 THEN 3
                     WHEN f.income_thousands < 150 THEN 4
                     WHEN f.income_thousands < 200 THEN 5
                     WHEN f.income_thousands < 300 THEN 6
                     ELSE 7
                END AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')                AS denial_reason,
       count(*)               AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 1) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_under_50k) AS DECIMAL(24,8)), 2)           AS inc_under_50k,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 2) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_50k_to_74k) AS DECIMAL(24,8)), 2)          AS inc_50k_to_74k,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 3) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_75k_to_99k) AS DECIMAL(24,8)), 2)          AS inc_75k_to_99k,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 4) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_100k_to_149k) AS DECIMAL(24,8)), 2)        AS inc_100k_to_149k,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 5) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_150k_to_199k) AS DECIMAL(24,8)), 2)        AS inc_150k_to_199k,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 6) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_200k_to_299k) AS DECIMAL(24,8)), 2)        AS inc_200k_to_299k,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 7) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_300k_and_over) AS DECIMAL(24,8)), 2)       AS inc_300k_and_over,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 8) AS DECIMAL(24,8))
             / CAST(max(n.apps_inc_not_reported) AS DECIMAL(24,8)), 2) AS inc_not_reported
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
```

</details>

The bottom row falls at every step of income: 50.82 citations per 100
applications under 50,000 dollars down to 16.22 above 300,000, a factor of 3.1.
Income not reported sits at 22.01.

**Debt-to-income is three fifths of that fall on its own.** It drops 21.03
points, from 23.44 to 2.41, against a total fall of 34.60. Credit history
supplies another 7.99. The two together are 84 percent of the decline and the
remaining eight reasons share the last sixth.

**Collateral does not move.** It reads 5.10, 4.83, 4.75, 4.43, 4.35, 4.43 and
4.78 across the seven named bands, a range of three quarters of a point against
debt-to-income's twenty-one. It is the only reason here effectively independent
of income.

The consequence is a crossover. **In the top income band collateral is the
largest single denial reason at 4.78**, ahead of credit history at 2.80 and
debt-to-income at 2.41; in the bottom band debt-to-income is 4.6 times
collateral's size. That is what the arithmetic predicts. The debt-to-income test
has income in its denominator, so it gets easier to pass as income rises, while
the collateral test is about the house, and a more expensive house is harder to
appraise.

### D2. Denial Reason by Loan Type

*Every cell is the number of times this reason was cited per 100 applications
the column group filed, purchased loans excluded. It is a rate, not a share of
the column: a column sums to that group's denial rate times its reasons per
denial, and the bottom row prints that total.*

| denial_reason | reason_occurrences | conventional | fha | va | rhs_fsa |
|---|---|---|---|---|---|
| Debt-to-income ratio | 135,207 | 8.78 | 6.41 | 3.31 | 5.08 |
| Credit history | 89,302 | 5.76 | 4.23 | 3.75 | 2.59 |
| Collateral | 71,778 | 4.56 | 4.25 | 2.89 | 1.87 |
| Other | 49,153 | 3.15 | 2.30 | 2.66 | 4.66 |
| Credit application incomplete | 24,663 | 1.42 | 2.72 | 2.61 | 0.57 |
| Unverifiable information | 16,800 | 1.04 | 1.32 | 0.68 | 0.93 |
| Insufficient cash (downpayment, closing costs) | 12,915 | 0.71 | 1.91 | 0.82 | 1.14 |
| Employment history | 6,437 | 0.37 | 0.75 | 0.48 | 0.78 |
| Exempt (partially exempt filer) | 4,592 | 0.32 | 0.00 | 0.00 | 0.00 |
| Mortgage insurance denied | 515 | 0.03 | 0.01 | 0.01 | 0.00 |
| All reasons | 411,362 | 26.15 | 23.91 | 17.22 | 17.62 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=D2">Query D2</a></summary>

```sql
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE p.loan_type = '1') AS apps_conventional,
           count(*) FILTER (WHERE p.loan_type = '2') AS apps_fha,
           count(*) FILTER (WHERE p.loan_type = '3') AS apps_va,
           count(*) FILTER (WHERE p.loan_type = '4') AS apps_rhs_fsa
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           p.loan_type AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')         AS denial_reason,
       count(*)        AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '1') AS DECIMAL(24,8))
             / CAST(max(n.apps_conventional) AS DECIMAL(24,8)), 2) AS conventional,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '2') AS DECIMAL(24,8))
             / CAST(max(n.apps_fha) AS DECIMAL(24,8)), 2)          AS fha,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '3') AS DECIMAL(24,8))
             / CAST(max(n.apps_va) AS DECIMAL(24,8)), 2)           AS va,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '4') AS DECIMAL(24,8))
             / CAST(max(n.apps_rhs_fsa) AS DECIMAL(24,8)), 2)      AS rhs_fsa
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
```

</details>

**Conventional is the highest column in the table at 26.15, not the flattest**,
with FHA at 23.91, USDA at 17.62 and VA lowest at 17.22. The underlying denial
rates are 20.30, 19.34, 13.37 and 14.63 percent.

The two channels fail differently and the split is clean. **FHA runs above
conventional on the three operational reasons**: insufficient cash 1.91 against
0.71, a factor of 2.7; credit application incomplete 2.72 against 1.42;
employment history 0.75 against 0.37. These are the reasons a borrower with a
thin file and little saved runs into, which is the borrower FHA exists to serve.

**Conventional runs above FHA on the two capacity tests**, debt-to-income 8.78
against 6.41 and credit history 5.76 against 4.23. FHA permits higher ratios, so
applications that fail the conventional test can pass the FHA one.

**VA's advantage is almost entirely debt-to-income.** At 3.31 it is 2.7 times
below conventional's 8.78, and that single row is 5.47 of the 8.93 points
separating the two columns overall.

### D3. Denial Reason by Loan Purpose

*Every cell is the number of times this reason was cited per 100 applications
the column group filed, purchased loans excluded. It is a rate, not a share of
the column: a column sums to that group's denial rate times its reasons per
denial, and the bottom row prints that total.*

| denial_reason | reason_occurrences | home_purchase | refinancing | cash_out_refi | home_improvement | other_purpose | not_applicable |
|---|---|---|---|---|---|---|---|
| Debt-to-income ratio | 135,207 | 4.00 | 9.53 | 6.64 | 16.37 | 16.38 | 0.42 |
| Credit history | 89,302 | 1.93 | 4.79 | 4.61 | 12.17 | 12.94 | 0.42 |
| Collateral | 71,778 | 2.56 | 3.76 | 4.62 | 8.44 | 7.32 | 6.72 |
| Other | 49,153 | 1.97 | 3.39 | 2.70 | 4.85 | 5.14 | 2.94 |
| Credit application incomplete | 24,663 | 0.88 | 1.80 | 3.33 | 1.36 | 1.92 | 2.94 |
| Unverifiable information | 16,800 | 0.94 | 0.96 | 1.06 | 1.40 | 1.11 | 1.68 |
| Insufficient cash (downpayment, closing costs) | 12,915 | 1.23 | 0.75 | 0.83 | 0.10 | 0.17 | 0.42 |
| Employment history | 6,437 | 0.42 | 0.27 | 0.33 | 0.48 | 0.46 | 0.00 |
| Exempt (partially exempt filer) | 4,592 | 0.21 | 0.31 | 0.25 | 0.38 | 0.48 | 0.42 |
| Mortgage insurance denied | 515 | 0.04 | 0.01 | 0.02 | 0.03 | 0.03 | 0.00 |
| All reasons | 411,362 | 14.17 | 25.57 | 24.37 | 45.58 | 45.96 | 15.97 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=D3">Query D3</a></summary>

```sql
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE p.loan_purpose = '1')  AS apps_home_purchase,
           count(*) FILTER (WHERE p.loan_purpose = '31') AS apps_refinancing,
           count(*) FILTER (WHERE p.loan_purpose = '32') AS apps_cash_out_refi,
           count(*) FILTER (WHERE p.loan_purpose = '2')  AS apps_home_improvement,
           count(*) FILTER (WHERE p.loan_purpose = '4')  AS apps_other_purpose,
           count(*) FILTER (WHERE p.loan_purpose = '5')  AS apps_not_applicable
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           p.loan_purpose AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')             AS denial_reason,
       count(*)            AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '1') AS DECIMAL(24,8))
             / CAST(max(n.apps_home_purchase) AS DECIMAL(24,8)), 2)    AS home_purchase,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '31') AS DECIMAL(24,8))
             / CAST(max(n.apps_refinancing) AS DECIMAL(24,8)), 2)      AS refinancing,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '32') AS DECIMAL(24,8))
             / CAST(max(n.apps_cash_out_refi) AS DECIMAL(24,8)), 2)    AS cash_out_refi,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '2') AS DECIMAL(24,8))
             / CAST(max(n.apps_home_improvement) AS DECIMAL(24,8)), 2) AS home_improvement,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '4') AS DECIMAL(24,8))
             / CAST(max(n.apps_other_purpose) AS DECIMAL(24,8)), 2)    AS other_purpose,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '5') AS DECIMAL(24,8))
             / CAST(max(n.apps_not_applicable) AS DECIMAL(24,8)), 2)   AS not_applicable
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
```

</details>

**The largest structural finding in this section.** The bottom row runs from
14.17 citations per 100 applications on home purchase to 45.58 on home
improvement and 45.96 on other purpose, a factor of 3.2. The underlying denial
rates are 10.78 percent against 35.13 and 35.84.

**Buying a house is by a wide margin the safest thing to apply for in this
register, and the small loans against a house you already own are the riskiest.**
[A5](#a5-market-profile-by-loan-purpose) showed that purchases are only 53.31
percent of loans; this says what the other 46.69 percent is up against.

Debt-to-income drives it: 16.37 and 16.38 on home improvement and other purpose
against 4.00 on home purchase, a factor of 4.1. Credit history follows at 12.17
and 12.94 against 1.93.

Two reasons keep their shape regardless of denominator, which is worth noting
because it means those findings never depended on one. **Insufficient cash is the
purchase reason**, 1.23 on home purchase against 0.10 on home improvement, a
factor of 12: you need a downpayment to buy a house and not to improve one.
**Credit application incomplete is the cash-out refinancing reason**, 3.33
against 0.88, because it is the most document-heavy product in the register.

### D4. Denial Reason by Applicant Race

*Every cell is the number of times this reason was cited per 100 applications
the column group filed, purchased loans excluded. It is a rate, not a share of
the column: a column sums to that group's denial rate times its reasons per
denial, and the bottom row prints that total.*

| denial_reason | reason_occurrences | white | black | asian | amer_indian | nhpi | two_or_more | joint | free_form | race_not_available |
|---|---|---|---|---|---|---|---|---|---|---|
| Debt-to-income ratio | 135,207 | 7.88 | 13.43 | 8.85 | 16.43 | 20.77 | 15.91 | 5.47 | 26.53 | 7.96 |
| Credit history | 89,302 | 5.30 | 10.49 | 3.50 | 12.83 | 12.20 | 13.09 | 4.88 | 21.35 | 5.24 |
| Collateral | 71,778 | 4.15 | 6.27 | 4.59 | 6.85 | 6.71 | 7.41 | 3.96 | 9.42 | 4.77 |
| Other | 49,153 | 2.80 | 4.62 | 2.77 | 5.81 | 5.19 | 5.26 | 2.35 | 7.69 | 3.45 |
| Credit application incomplete | 24,663 | 1.32 | 2.11 | 1.22 | 2.15 | 1.74 | 2.90 | 1.04 | 0.63 | 2.22 |
| Unverifiable information | 16,800 | 0.88 | 1.36 | 1.58 | 1.42 | 1.59 | 1.57 | 0.77 | 3.14 | 1.22 |
| Insufficient cash (downpayment, closing costs) | 12,915 | 0.71 | 1.32 | 1.00 | 1.44 | 1.32 | 1.54 | 0.82 | 1.57 | 0.78 |
| Employment history | 6,437 | 0.38 | 0.57 | 0.45 | 0.76 | 0.81 | 0.68 | 0.44 | 0.16 | 0.36 |
| Exempt (partially exempt filer) | 4,592 | 0.27 | 0.26 | 0.21 | 0.23 | 0.18 | 0.21 | 0.20 | 0.00 | 0.40 |
| Mortgage insurance denied | 515 | 0.03 | 0.05 | 0.01 | 0.06 | 0.00 | 0.05 | 0.04 | 0.00 | 0.03 |
| All reasons | 411,362 | 23.73 | 40.47 | 24.18 | 47.99 | 50.51 | 48.63 | 19.96 | 70.49 | 26.44 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=D4">Query D4</a></summary>

```sql
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE a.derived_race = 'White')                                     AS apps_white,
           count(*) FILTER (WHERE a.derived_race = 'Black or African American')                 AS apps_black,
           count(*) FILTER (WHERE a.derived_race = 'Asian')                                     AS apps_asian,
           count(*) FILTER (WHERE a.derived_race = 'American Indian or Alaska Native')          AS apps_amer_indian,
           count(*) FILTER (WHERE a.derived_race = 'Native Hawaiian or Other Pacific Islander') AS apps_nhpi,
           count(*) FILTER (WHERE a.derived_race = '2 or more minority races')                  AS apps_two_or_more,
           count(*) FILTER (WHERE a.derived_race = 'Joint')                                     AS apps_joint,
           count(*) FILTER (WHERE a.derived_race = 'Free Form Text Only')                       AS apps_free_form,
           count(*) FILTER (WHERE a.derived_race = 'Race Not Available')                        AS apps_race_not_available
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           a.derived_race AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')               AS denial_reason,
       count(*)              AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'White') AS DECIMAL(24,8))
             / CAST(max(n.apps_white) AS DECIMAL(24,8)), 2)              AS white,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Black or African American') AS DECIMAL(24,8))
             / CAST(max(n.apps_black) AS DECIMAL(24,8)), 2)              AS black,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Asian') AS DECIMAL(24,8))
             / CAST(max(n.apps_asian) AS DECIMAL(24,8)), 2)              AS asian,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'American Indian or Alaska Native') AS DECIMAL(24,8))
             / CAST(max(n.apps_amer_indian) AS DECIMAL(24,8)), 2)        AS amer_indian,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Native Hawaiian or Other Pacific Islander') AS DECIMAL(24,8))
             / CAST(max(n.apps_nhpi) AS DECIMAL(24,8)), 2)               AS nhpi,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '2 or more minority races') AS DECIMAL(24,8))
             / CAST(max(n.apps_two_or_more) AS DECIMAL(24,8)), 2)        AS two_or_more,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Joint') AS DECIMAL(24,8))
             / CAST(max(n.apps_joint) AS DECIMAL(24,8)), 2)              AS joint,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Free Form Text Only') AS DECIMAL(24,8))
             / CAST(max(n.apps_free_form) AS DECIMAL(24,8)), 2)          AS free_form,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Race Not Available') AS DECIMAL(24,8))
             / CAST(max(n.apps_race_not_available) AS DECIMAL(24,8)), 2) AS race_not_available
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
```

</details>

The bottom row runs from 19.96 for Joint to 70.49 for Free Form Text Only, which
holds 637 applications and is shown rather than compared. **Among the categories
with more than 100,000 applications the range is narrow**: White 23.73, Asian
24.18, Race Not Available 26.44.

**Debt-to-income and credit history carry nearly all of the spread between
groups.** Debt-to-income runs 5.47 to 26.53 and credit history 3.50 to 21.35,
while collateral runs only 3.96 to 9.42 and no reason below it spans more than
six points.

**Asian applications are the clearest pattern, and it is a substitution rather
than a surplus.** Their bottom row of 24.18 is within half a point of White's
23.73, and the underlying denial rates are 18.55 and 18.49 percent, closer than
any other pair. Inside that near-identical total the mix differs: credit history
3.50 against White's 5.30, the lowest figure in that row, while unverifiable
information at 1.58 is the highest of any category above 100,000 applications.
Same rate, different reasons.

Race Not Available is ordinary on the capacity tests, within a tenth of a point
of White on both, and high on the procedural ones: credit application incomplete
2.22 against 1.32. An application missing a race field is more often also an
application that was never completed, which is a statement about the filing.

### D5. Denial Reason by Applicant Sex

*Every cell is the number of times this reason was cited per 100 applications
the column group filed, purchased loans excluded. It is a rate, not a share of
the column: a column sums to that group's denial rate times its reasons per
denial, and the bottom row prints that total.*

| denial_reason | reason_occurrences | male | female | joint | sex_not_available |
|---|---|---|---|---|---|
| Debt-to-income ratio | 135,207 | 9.83 | 10.47 | 6.26 | 6.05 |
| Credit history | 89,302 | 5.78 | 6.90 | 4.77 | 4.51 |
| Collateral | 71,778 | 5.34 | 4.80 | 3.39 | 4.34 |
| Other | 49,153 | 3.45 | 3.54 | 2.29 | 3.21 |
| Credit application incomplete | 24,663 | 1.75 | 1.54 | 1.06 | 2.37 |
| Unverifiable information | 16,800 | 1.28 | 1.10 | 0.78 | 0.99 |
| Insufficient cash (downpayment, closing costs) | 12,915 | 0.92 | 0.97 | 0.65 | 0.56 |
| Employment history | 6,437 | 0.43 | 0.48 | 0.35 | 0.29 |
| Exempt (partially exempt filer) | 4,592 | 0.27 | 0.30 | 0.19 | 0.61 |
| Mortgage insurance denied | 515 | 0.03 | 0.04 | 0.03 | 0.03 |
| All reasons | 411,362 | 29.08 | 30.13 | 19.78 | 22.97 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=D5">Query D5</a></summary>

```sql
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE a.derived_sex = 'Male')              AS apps_male,
           count(*) FILTER (WHERE a.derived_sex = 'Female')            AS apps_female,
           count(*) FILTER (WHERE a.derived_sex = 'Joint')             AS apps_joint,
           count(*) FILTER (WHERE a.derived_sex = 'Sex Not Available') AS apps_sex_not_available
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           a.derived_sex AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')              AS denial_reason,
       count(*)             AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Male') AS DECIMAL(24,8))
             / CAST(max(n.apps_male) AS DECIMAL(24,8)), 2)              AS male,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Female') AS DECIMAL(24,8))
             / CAST(max(n.apps_female) AS DECIMAL(24,8)), 2)            AS female,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Joint') AS DECIMAL(24,8))
             / CAST(max(n.apps_joint) AS DECIMAL(24,8)), 2)             AS joint,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = 'Sex Not Available') AS DECIMAL(24,8))
             / CAST(max(n.apps_sex_not_available) AS DECIMAL(24,8)), 2) AS sex_not_available
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
```

</details>

**The flattest of the six tables, and the two named individual categories trade
places by reason rather than one leading throughout.**

Female applications total 30.13 against male 29.08, a gap of 1.05 points on a
base of about thirty, consistent with the denial rates of 23.31 and 22.71 percent
in C2a. The gap is not spread evenly.

**Female runs higher on the borrower tests**, debt-to-income 10.47 against 9.83
and credit history 6.90 against 5.78, worth 1.76 points together, more than the
whole difference between the columns. **Male runs higher on the property and
documentation tests**, collateral 5.34 against 4.80, unverifiable information
1.28 against 1.10, incomplete 1.75 against 1.54, giving 0.93 points back.

So the net difference is small because the two sets nearly cancel. A table
reporting only a total would show a gap of a point and say nothing; the reason
breakdown shows two offsetting differences of roughly twice that size.

Sex Not Available's one standout is credit application incomplete at 2.37, the
highest in that row, with the exempt code at 0.61, also the highest: the same
pattern as Race Not Available and as C6.

### D6. Denial Reason by Applicant Age Band

*Every cell is the number of times this reason was cited per 100 applications
the column group filed, purchased loans excluded. It is a rate, not a share of
the column: a column sums to that group's denial rate times its reasons per
denial, and the bottom row prints that total.*

| denial_reason | reason_occurrences | under_25 | age_25_to_34 | age_35_to_44 | age_45_to_54 | age_55_to_64 | age_65_to_74 | over_74 | age_not_provided |
|---|---|---|---|---|---|---|---|---|---|
| Debt-to-income ratio | 135,207 | 5.37 | 5.47 | 7.48 | 9.51 | 11.12 | 11.74 | 12.68 | 2.16 |
| Credit history | 89,302 | 4.68 | 3.53 | 5.33 | 6.89 | 6.96 | 6.22 | 6.61 | 2.15 |
| Collateral | 71,778 | 3.66 | 4.11 | 4.79 | 4.83 | 4.42 | 4.43 | 5.11 | 3.00 |
| Other | 49,153 | 3.00 | 2.42 | 2.91 | 3.31 | 3.41 | 3.27 | 3.79 | 3.63 |
| Credit application incomplete | 24,663 | 1.18 | 1.09 | 1.41 | 1.73 | 1.89 | 1.82 | 1.97 | 1.27 |
| Unverifiable information | 16,800 | 1.09 | 0.90 | 1.07 | 1.13 | 1.13 | 0.98 | 1.03 | 1.04 |
| Insufficient cash (downpayment, closing costs) | 12,915 | 1.62 | 1.01 | 0.86 | 0.79 | 0.66 | 0.59 | 0.68 | 0.43 |
| Employment history | 6,437 | 1.15 | 0.53 | 0.42 | 0.42 | 0.35 | 0.19 | 0.08 | 0.16 |
| Exempt (partially exempt filer) | 4,592 | 0.21 | 0.20 | 0.22 | 0.26 | 0.29 | 0.28 | 0.26 | 1.41 |
| Mortgage insurance denied | 515 | 0.08 | 0.05 | 0.04 | 0.03 | 0.02 | 0.01 | 0.01 | 0.02 |
| All reasons | 411,362 | 22.05 | 19.31 | 24.54 | 28.88 | 30.25 | 29.53 | 32.22 | 15.27 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=D6">Query D6</a></summary>

```sql
WITH denominator AS (
    SELECT
           count(*) FILTER (WHERE a.applicant_age = '<25')   AS apps_under_25,
           count(*) FILTER (WHERE a.applicant_age = '25-34') AS apps_age_25_to_34,
           count(*) FILTER (WHERE a.applicant_age = '35-44') AS apps_age_35_to_44,
           count(*) FILTER (WHERE a.applicant_age = '45-54') AS apps_age_45_to_54,
           count(*) FILTER (WHERE a.applicant_age = '55-64') AS apps_age_55_to_64,
           count(*) FILTER (WHERE a.applicant_age = '65-74') AS apps_age_65_to_74,
           count(*) FILTER (WHERE a.applicant_age = '>74')   AS apps_over_74,
           count(*) FILTER (WHERE a.applicant_age = '8888')  AS apps_age_not_provided
    FROM marts.fct_application f
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    WHERE f.action_taken <> '6'
),
denied AS (
    SELECT COALESCE(r.label, 'Exempt (partially exempt filer)') AS denial_reason,
           a.applicant_age AS grp
    FROM marts.fct_application f
    JOIN marts.br_denial_reason b
      ON b.application_sk = f.application_sk
     AND b.activity_year  = f.activity_year
    JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
    LEFT JOIN ref.ref_code r
      ON r.code_field = 'denial_reason_1'
     AND r.code_value = b.denial_reason_code
    WHERE f.action_taken IN ('3', '7')
)
SELECT COALESCE(d.denial_reason, 'All reasons')             AS denial_reason,
       count(*)            AS reason_occurrences,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '<25') AS DECIMAL(24,8))
             / CAST(max(n.apps_under_25) AS DECIMAL(24,8)), 2)         AS under_25,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '25-34') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_25_to_34) AS DECIMAL(24,8)), 2)     AS age_25_to_34,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '35-44') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_35_to_44) AS DECIMAL(24,8)), 2)     AS age_35_to_44,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '45-54') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_45_to_54) AS DECIMAL(24,8)), 2)     AS age_45_to_54,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '55-64') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_55_to_64) AS DECIMAL(24,8)), 2)     AS age_55_to_64,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '65-74') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_65_to_74) AS DECIMAL(24,8)), 2)     AS age_65_to_74,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '>74') AS DECIMAL(24,8))
             / CAST(max(n.apps_over_74) AS DECIMAL(24,8)), 2)          AS over_74,
       round(CAST(100.0 * count(*) FILTER (WHERE d.grp = '8888') AS DECIMAL(24,8))
             / CAST(max(n.apps_age_not_provided) AS DECIMAL(24,8)), 2) AS age_not_provided
FROM denied d
CROSS JOIN denominator n
GROUP BY GROUPING SETS ((d.denial_reason), ())
ORDER BY GROUPING(d.denial_reason), 2 DESC;
```

</details>

**Two reasons form ladders running in opposite directions, and they cross.**

The bottom row rises with age from the 25 to 34 band onward: 19.31, 24.54, 28.88,
30.25, 29.53, 32.22. Applicants under 25 sit at 22.05, between the first two, so
the shape is a rise with age rather than a penalty at both ends.

**Debt-to-income rises at every step from 25 to 34 upward**: 5.47, 7.48, 9.51,
11.12, 11.74, 12.68, a factor of 2.3, and it is the largest reason in every named
band.

**Employment history falls at every step**, 1.15 under 25, then 0.53, 0.42, 0.42,
0.35, 0.19 and 0.08 above 74. A factor of 14, the widest spread any reason shows
across age, and the one pattern here that reads like a biography rather than a
statistic. Insufficient cash and mortgage insurance denied follow the same shape.

So the youngest and oldest bands reach similar totals for opposite reasons.
**This is the mirror of the loan-to-value ladder in
[C3b](#c3b-loan-characteristics-by-applicant-age-band)**, where leverage falls
from 90 to 48 across the same bands: the oldest borrowers are constrained by
income while holding the most equity, which is exactly the combination that
produces a debt-to-income refusal and not a collateral one.

</details>

---

## E. Lender Performance

<details>
<summary><b>Twelve queries: outcomes, loan characteristics, product mix across seven dimensions, pricing and geographic reach, for all 1,139 lenders</b></summary>

**1,139 institutions filed applications in New York over the four years**, and
there is no filter on where a lender is headquartered: 221 are in New York and
918 are not, across all fifty states. The only filter is on the applications,
which are all in New York.

Every query returns all 1,139 rows. The tables here print the three largest and
the three smallest with an elision row between them, and the run-live link
returns the rest.

**Two problems had to be solved before a lender could be counted at all.** HMDA
files an institution name once per year, and 1,279 LEIs carry more than one
spelling across the four years, almost all case or punctuation, so joining the
dimension year by year would split one lender into several rows. And a name is
not an identifier: nine names in the New York data are shared by two different
LEIs, six of them unrelated banks, so FIRST BANK of Burkburnett TX and FIRST BANK
of Hamilton NJ would have been silently merged. The grain is therefore the LEI,
and the label widens only as far as it must, adding the city where the name alone
is ambiguous and the LEI where the city does not settle it either.

**Market share appears in E1a only.** Everywhere else a share is of that lender's
own originated loans, so a row describes its product mix and sums to 100 across.
The two questions are different and the second one needs no market denominator.

**No volume floor.** Across all 1,139 lenders, 507 filed fewer than 10
applications and 119 show a denial rate of exactly 100.00. Among the 195 with
1,000 or more the denial rate runs 0.70 to 68.57, which is a real spread. Nothing
is hidden, and `total_applications` is column 2 so no rate is ever read without
the count it rests on.

### E1a. Lender Outcomes and Market Share

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

| lender_name | total_applications | originated_loans | total_loan_amount | mkt_share_loans_pct | mkt_share_amount_pct | approval_rate | denial_rate | incomplete_rate | withdrawal_rate |
|---|---|---|---|---|---|---|---|---|---|
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 4.5246 | 4.1800 | 53.39 | 35.57 | 4.86 | 6.17 |
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 5.2482 | 3.5040 | 71.94 | 20.71 | 0.19 | 7.16 |
| JPMorgan Chase Bank, NA | 56,863 | 38,206 | 27,276,235,000 | 4.0159 | 7.3438 | 69.12 | 10.16 | 8.66 | 12.06 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| The Lincoln National Life Insurance Company | 1 | 1 |  | 0.0001 | 0.0000 | 100.00 | 0.00 | 0.00 | 0.00 |
| Bank of the West (San Francisco, CA) | 1 | 0 |  | 0.0000 | 0.0000 | 0.00 | 100.00 | 0.00 | 0.00 |
| REPUBLIC BANK & TRUST | 1 | 1 | 1,505,000 | 0.0001 | 0.0004 | 100.00 | 0.00 | 0.00 | 0.00 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E1a">Query E1a</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                               AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                           AS originated_loans,
       sum(f.loan_amount) FILTER (WHERE f.action_taken = '1')                  AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,8))
             / CAST(sum(count(*) FILTER (WHERE f.action_taken = '1')) OVER () AS DECIMAL(24,8)), 4)
                                                                              AS mkt_share_loans_pct,
       round(CAST(100.0 * COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8))
             / CAST(sum(COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)) OVER () AS DECIMAL(24,8)), 4)
                                                                              AS mkt_share_amount_pct,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS denial_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '5') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS incomplete_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '4') AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                            AS withdrawal_rate
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 2 DESC, l.lei;
```

</details>

**The two market shares are different numbers, not a rounding difference.**
ROCKET MORTGAGE holds 5.2482 percent of the state's originated loans and 3.5040
percent of its mortgage dollars, a third less. JPMorgan runs the other way,
4.0159 and 7.3438, nearly double. Citizens is the largest lender by
applications, Rocket by loans and JPMorgan by money.

Four decimal places here because the largest share in the table is 5.2483 percent
and 979 of the 1,139 lenders are below 0.1. **This is the only table in the
section carrying market share**; E2 to E10 give each lender's own product mix
instead, and a lender's share of any single category is (its share there times
column 5) divided by that category's own share of the market.

**Among the 25 largest lenders the denial rate runs from 1.90 to 50.71 percent
and approval from 12.01 to 88.54**, and the two extremes took 13,494 and 32,936
applications, so the spread is not small-sample noise.

The four rates come apart in useful ways. CROSSCOUNTRY MORTGAGE denies 4.48
percent and withdraws 25.56. NEWREZ LLC ends 41.52 percent of its applications
with no decision either way. DISCOVER BANK leaves 28.55 percent incomplete
against the market's 4.92.

This table says these lenders behave very differently. It does not say they are
doing the same thing differently, which is the claim a reader will jump to;
[F3](#f3-lender-outcomes-on-one-product) is what tests it.

### E1b. Lender Loan Characteristics

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

| lender_name | total_applications | originated_loans | median_applicant_income | median_property_value | median_loan_amount | median_loan_to_value | median_loan_to_income | median_interest_rate |
|---|---|---|---|---|---|---|---|---|
| CITIZENS BANK, NA | 82,894 | 43,046 | 146,000 | 625,000 | 195,000 | 71.43 | 1.35 | 7.400 |
| ROCKET MORTGAGE | 77,402 | 49,930 | 107,000 | 395,000 | 205,000 | 71.00 | 2.15 | 6.375 |
| JPMorgan Chase Bank, NA | 56,863 | 38,206 | 149,000 | 695,000 | 425,000 | 70.00 | 2.47 | 5.990 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| The Lincoln National Life Insurance Company | 1 | 1 |  | 38,355,000 |  | 53.84 |  | 5.850 |
| Bank of the West (San Francisco, CA) | 1 | 0 |  |  |  |  |  |  |
| REPUBLIC BANK & TRUST | 1 | 1 | 1,496,000 | 3,405,000 | 1,505,000 | 44.12 | 1.01 | 4.875 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E1b">Query E1b</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                          AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                       AS originated_loans,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' AND f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                          AS median_applicant_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.property_value END)
             AS DECIMAL(24,8)))                                          AS median_property_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_amount END)
             AS DECIMAL(24,8)))                                          AS median_loan_amount,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.loan_to_value_ratio END)
             AS DECIMAL(24,8)), 2)                                       AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' AND f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                       AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)                                       AS median_interest_rate
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 2 DESC, l.lei;
```

</details>

**The ranges here are the widest on this page, and almost all of it is product
mix.** Median loan amount runs from 65,000 dollars to 645,000 among the 25
largest, a factor of ten; median interest rate from 4.500 to 8.610 percent, 411
basis points.

The lenders with small loans and high rates are lending in second position.
DISCOVER BANK is 85.7 percent subordinate lien, Broadview 79.0 percent with 95.1
percent open-end lines, against Citibank at 6.3 and JPMorgan at 1.4. **So the
rate column needs two caveats**: four-year pooling across a 237.5 basis point
move, and a product mix that is priced differently by design.

That same check separates two different routes to a small median loan. **Second
position against an expensive house** is Broadview: median property 335,000,
median loan 65,000. **First position against a cheap house** is Community Bank:
only 22.3 percent subordinate, median property 195,000, median loan 105,000 at
79.99 percent of value. Similar medians, nothing else alike.

### E2. Product Mix by Loan Type

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | conventional_loans_pct | conventional_loan_amount | fha_loans_pct | fha_loan_amount | va_loans_pct | va_loan_amount | rhs_fsa_loans_pct | rhs_fsa_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 74.34 | 9,739,560,000 | 19.32 | 2,383,000,000 | 6.34 | 891,810,000 | 0.00 | 0 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 98.92 | 15,382,090,000 | 0.87 | 109,355,000 | 0.21 | 33,885,000 | 0.00 | 0 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 81.24 | 15,469,500,000 | 15.98 | 3,143,885,000 | 2.64 | 455,090,000 | 0.14 | 9,400,000 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E2">Query E2</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                               AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                           AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)     AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '1') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)
                                                                              AS conventional_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '1'), 0)
                                                                              AS conventional_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '2') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)
                                                                              AS fha_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '2'), 0)
                                                                              AS fha_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '3') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)
                                                                              AS va_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '3'), 0)
                                                                              AS va_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '4') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)
                                                                              AS rhs_fsa_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_type = '4'), 0)
                                                                              AS rhs_fsa_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

**Four of the 21 lenders with more than 10,000 originated loans write nothing but
conventional**: Broadview, Empower, Jovia and Discover all read 100.00.

**FHA share separates the mortgage companies from the deposit-takers, and the
register confirms it independently.** Rocket is at 19.32 percent, Homestead 17.84,
NEWREZ 16.00, United Wholesale 15.98, loanDepot 14.60, Premium 14.48,
CrossCountry 11.85. All seven carry `agency_code` 7 in the institution dimension,
which is HUD, the HMDA supervisor for non-depository lenders. Every bank and
credit union in the table carries 5 for the NCUA or 9 for the CFPB and sits below
7.5 percent, most below 1.5: Bank of America 0.79, TD Bank 0.35, Citibank 0.08,
Teachers 0.01.

It is not about size. Rocket and United Wholesale are among the largest lenders
in the state; Homestead and Premium are among the smallest shown. What they share
is being mortgage companies rather than deposit-takers.

### E3. Product Mix by Loan Purpose

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | home_purchase_loans_pct | home_purchase_loan_amount | refinancing_loans_pct | refinancing_loan_amount | cash_out_refi_loans_pct | cash_out_refi_loan_amount | home_improvement_loans_pct | home_improvement_loan_amount | other_purpose_loans_pct | other_purpose_loan_amount | not_applicable_loans_pct | not_applicable_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 29.51 | 4,886,840,000 | 9.89 | 1,407,445,000 | 54.77 | 6,197,910,000 | 1.52 | 127,905,000 | 4.30 | 394,270,000 | 0.00 | 0 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 25.92 | 8,344,255,000 | 23.90 | 3,078,760,000 | 3.13 | 597,945,000 | 26.58 | 1,975,265,000 | 20.46 | 1,529,105,000 | 0.00 | 0 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 82.38 | 15,815,400,000 | 4.82 | 1,040,670,000 | 12.80 | 2,221,805,000 | 0.00 | 0 | 0.00 | 0 | 0.00 | 0 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E3">Query E3</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                 AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')               AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)              AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '1') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS home_purchase_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '1'), 0)    AS home_purchase_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '31') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)        AS refinancing_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '31'), 0)      AS refinancing_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '32') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS cash_out_refi_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '32'), 0)    AS cash_out_refi_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '2') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS home_improvement_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '2'), 0) AS home_improvement_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '4') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS other_purpose_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '4'), 0)    AS other_purpose_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '5') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS not_applicable_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND p.loan_purpose = '5'), 0)   AS not_applicable_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

**This table sorts lenders into three businesses and the numbers are blunt.**

*Purchase shops.* Premium Mortgage is **96.59 percent home purchase**, Homestead
94.11. United Wholesale reports 0.00 on both home improvement and other purpose.

*A cash-out refinancing shop.* **ROCKET MORTGAGE is 54.77 percent cash-out
refinancing**, against a market figure of 13.14. More than half of everything the
largest originator in the state writes is a cash-out refinance.

*Second-lien shops.* Broadview is **61.01 percent home improvement**, Hudson
Valley 46.52. ESL is **40.97 percent other purpose** with only 4.81 percent home
purchase, the lowest of any large lender.

*And one full-service bank.* CITIZENS BANK is the only large lender with no
dominant cell: 23.90 percent refinancing, its largest, with meaningful shares in
purchase, home improvement and other purpose as well.

Participation thins fast. 829 of the 1,139 lenders write at least one home
purchase loan, 612 a refinance, but only 380 home improvement and 364 other
purpose.

### E4. Product Mix by Loan Amount Band

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | amt_under_100k_loans_pct | amt_under_100k_loan_amount | amt_100k_to_249k_loans_pct | amt_100k_to_249k_loan_amount | amt_250k_to_499k_loans_pct | amt_250k_to_499k_loan_amount | amt_500k_to_749k_loans_pct | amt_500k_to_749k_loan_amount | amt_750k_to_999k_loans_pct | amt_750k_to_999k_loan_amount | amt_1m_and_over_loans_pct | amt_1m_and_over_loan_amount | amt_not_reported_loans_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 15.36 | 537,455,000 | 44.82 | 3,681,075,000 | 28.36 | 4,996,660,000 | 9.10 | 2,696,015,000 | 1.78 | 748,080,000 | 0.58 | 355,085,000 | 0.00 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 22.94 | 573,755,000 | 39.58 | 2,691,045,000 | 17.86 | 2,670,505,000 | 7.69 | 2,000,640,000 | 4.26 | 1,562,745,000 | 7.62 | 6,026,640,000 | 0.04 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 2.28 | 68,715,000 | 24.63 | 1,885,420,000 | 35.17 | 5,473,145,000 | 26.81 | 6,850,130,000 | 7.25 | 2,590,830,000 | 3.86 | 2,209,635,000 | 0.00 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E4">Query E4</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                 AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')               AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)              AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount < 100000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS amt_under_100k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount < 100000), 0)   AS amt_under_100k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 100000 AND f.loan_amount < 250000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_100k_to_249k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 100000 AND f.loan_amount < 250000), 0) AS amt_100k_to_249k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 250000 AND f.loan_amount < 500000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_250k_to_499k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 250000 AND f.loan_amount < 500000), 0) AS amt_250k_to_499k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 500000 AND f.loan_amount < 750000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_500k_to_749k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 500000 AND f.loan_amount < 750000), 0) AS amt_500k_to_749k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 750000 AND f.loan_amount < 1000000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS amt_750k_to_999k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 750000 AND f.loan_amount < 1000000), 0) AS amt_750k_to_999k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 1000000) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)    AS amt_1m_and_over_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_amount >= 1000000), 0)  AS amt_1m_and_over_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_amount IS NULL) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)  AS amt_not_reported_loans_pct
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

The six bands are round numbers on the actual distribution of originated loans,
whose quartiles are 115,000 and 485,000 dollars.

**The spread is extreme at both ends.** Broadview writes **67.38 percent of its
loans under 100,000 dollars** and ESL 61.22, against a market figure of 19.23.
Citibank writes **29.85 percent above a million and 12.34 percent between 750,000
and a million**, so 42.2 percent of its book is above 750,000 against a market
figure of 10.18. Wells Fargo is second at 23.08 and 10.94.

United Wholesale owns the middle, 26.81 percent in the 500,000 to 750,000 band.

**The last column is a coverage band, not a size band.** 2,115 originated loans
across 144 lenders carry no loan amount at all, 227 at JPMorgan and 119 at Wells
Fargo. Without it the six size bands would quietly cover 99.78 percent of a
lender's loans rather than all of them. It has no amount column beside it because
a loan with no amount contributes nothing to the dollars by definition.

### E5. Product Mix by Applicant Income Band

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | inc_under_50k_loans_pct | inc_under_50k_loan_amount | inc_50k_to_74k_loans_pct | inc_50k_to_74k_loan_amount | inc_75k_to_99k_loans_pct | inc_75k_to_99k_loan_amount | inc_100k_to_149k_loans_pct | inc_100k_to_149k_loan_amount | inc_150k_to_199k_loans_pct | inc_150k_to_199k_loan_amount | inc_200k_to_299k_loans_pct | inc_200k_to_299k_loan_amount | inc_300k_and_over_loans_pct | inc_300k_and_over_loan_amount | inc_not_reported_loans_pct | inc_not_reported_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 9.16 | 537,065,000 | 17.50 | 1,410,040,000 | 17.72 | 1,841,310,000 | 26.54 | 3,588,170,000 | 13.66 | 2,307,445,000 | 9.67 | 1,937,015,000 | 4.46 | 1,183,550,000 | 1.30 | 209,775,000 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 7.13 | 275,265,000 | 11.04 | 541,820,000 | 12.16 | 768,045,000 | 20.62 | 1,763,030,000 | 14.06 | 1,626,740,000 | 14.89 | 2,488,010,000 | 19.31 | 7,417,095,000 | 0.80 | 645,325,000 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 5.76 | 448,020,000 | 11.68 | 1,139,150,000 | 14.11 | 1,836,750,000 | 29.02 | 5,309,970,000 | 17.60 | 3,985,285,000 | 12.81 | 3,327,900,000 | 8.77 | 2,975,725,000 | 0.25 | 55,075,000 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E5">Query E5</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                  AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)               AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands > 0 AND f.income_thousands < 50) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS inc_under_50k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands > 0 AND f.income_thousands < 50), 0)     AS inc_under_50k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 50 AND f.income_thousands < 75) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS inc_50k_to_74k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 50 AND f.income_thousands < 75), 0)    AS inc_50k_to_74k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 75 AND f.income_thousands < 100) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)      AS inc_75k_to_99k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 75 AND f.income_thousands < 100), 0)    AS inc_75k_to_99k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 100 AND f.income_thousands < 150) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)    AS inc_100k_to_149k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 100 AND f.income_thousands < 150), 0)  AS inc_100k_to_149k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 150 AND f.income_thousands < 200) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)    AS inc_150k_to_199k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 150 AND f.income_thousands < 200), 0)  AS inc_150k_to_199k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 200 AND f.income_thousands < 300) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)    AS inc_200k_to_299k_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 200 AND f.income_thousands < 300), 0)  AS inc_200k_to_299k_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 300) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS inc_300k_and_over_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.income_thousands >= 300), 0) AS inc_300k_and_over_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND (f.income_thousands IS NULL OR f.income_thousands <= 0)) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)    AS inc_not_reported_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND (f.income_thousands IS NULL OR f.income_thousands <= 0)), 0)  AS inc_not_reported_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

The eight bands are the ones defined in C4a, so a lender's income profile reads
directly against the market's.

**Citibank is 43.74 percent above 300,000 dollars** against a market figure of
10.98, and Wells Fargo 35.85. At the other end **Community Bank is 15.35 percent
under 50,000** and Empower 14.81, against 6.48.

**The middle bands separate less than the ends.** The 100,000 to 149,000 band
runs 13.30 to 29.10 across the 21 largest lenders; the 300,000-plus band runs
1.37 to 43.74, a factor of 32. Lenders differ far more in how much of the top of
the income distribution they serve than in how much of the middle.

Income not reported is a lender characteristic, not noise: JPMorgan 12.01
percent and M&T 10.32 against a market figure of 8.09, while several large
lenders are below 1.

### E6. Interest Rate Distribution

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

| lender_name | total_applications | originated_loans | loans_with_rate | total_loan_amount | p10_interest_rate | p25_interest_rate | median_interest_rate | p75_interest_rate | p90_interest_rate |
|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 49,930.00 | 13,014,370,000 | 3.500 | 5.375 | 6.375 | 6.990 | 8.800 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 43,046.00 | 15,525,330,000 | 3.750 | 5.625 | 7.400 | 8.900 | 10.150 |
| United Wholesale Mortgage | 56,090 | 42,059 | 42,059.00 | 19,077,875,000 | 4.750 | 5.820 | 6.375 | 6.880 | 7.500 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0.00 | 0 |  |  |  |  |  |
| Union Bank and Trust Company | 2 | 0 | 0.00 | 0 |  |  |  |  |  |
| Bank of Hawaii | 2 | 0 | 0.00 | 0 |  |  |  |  |  |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E6">Query E6</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                       AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')   AS originated_loans,
       count(f.interest_rate) FILTER (WHERE f.action_taken = '1') AS loans_with_rate,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS total_loan_amount,
       round(CAST(percentile_disc(0.10) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p10_interest_rate,
       round(CAST(percentile_disc(0.25) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p25_interest_rate,
       round(CAST(percentile_disc(0.50) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)AS median_interest_rate,
       round(CAST(percentile_disc(0.75) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p75_interest_rate,
       round(CAST(percentile_disc(0.90) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken = '1' THEN f.interest_rate END)
             AS DECIMAL(24,8)), 3)    AS p90_interest_rate
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

The median column reproduces E1b's exactly, which is the check that the
percentiles cover the same population.

**Column 4 is the denominator the five percentiles rest on, and it is often not
column 3.** 34,269 originated loans, 3.6 percent of the market, carry no interest
rate at all. Pioneer Bank shows 1,071 originated loans and five percentiles that
are **one loan printed five times**; without column 4 that row reads as a priced
book of a thousand loans. Advantage Federal Credit Union shows 2,002 loans, none
with a rate, and five blanks that now explain themselves.

**The spread is the finding, not the median.** Among the fourteen largest lenders
the tenth-to-ninetieth spread runs from 2.38 points at Premium Mortgage to 6.90
at M&T, and the interquartile width from 1.00 to 3.28. **The four narrowest belong
to the four mortgage companies**, all at an interquartile width of about one
point. The widest belong to banks and credit unions at 2.0 to 3.3, and not
because banks price less consistently: a lender writing first mortgages, second
liens and open-end lines at once is pricing three products, so the percentiles of
its single rate column straddle all three.

**Zero is a reported rate and is counted as one.** 5,949 originated loans report
exactly zero, mostly open-end lines in second position, which is why Empower
reads 0.000 at p10. The filer is the authority on what it filed. They are 0.6
percent of originated loans, so they move nothing material, and every median rate
on this page treats them the same way.

### E7. Product Mix by Loan Term

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | term_to_10y_loans_pct | term_to_10y_loan_amount | term_10y_to_15y_loans_pct | term_10y_to_15y_loan_amount | term_15y_to_20y_loans_pct | term_15y_to_20y_loan_amount | term_20y_to_25y_loans_pct | term_20y_to_25y_loan_amount | term_25y_to_30y_loans_pct | term_25y_to_30y_loan_amount | term_over_30y_loans_pct | term_over_30y_loan_amount | term_not_reported_loans_pct | term_not_reported_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 1.33 | 98,440,000 | 8.65 | 916,420,000 | 16.25 | 1,135,815,000 | 1.54 | 164,555,000 | 72.23 | 10,697,200,000 | 0.00 | 1,940,000 | 0.00 | 0 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 0.40 | 416,860,000 | 2.01 | 321,740,000 | 0.35 | 37,770,000 | 71.31 | 5,832,935,000 | 25.92 | 8,915,575,000 | 0.00 | 450,000 | 0.00 | 0 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 0.12 | 13,130,000 | 2.80 | 394,740,000 | 0.96 | 108,590,000 | 0.16 | 23,850,000 | 95.88 | 18,511,665,000 | 0.08 | 25,900,000 | 0.00 | 0 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E7">Query E7</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                  AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)               AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months <= 120) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)         AS term_to_10y_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months <= 120), 0)       AS term_to_10y_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 120 AND f.loan_term_months <= 180) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS term_10y_to_15y_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 120 AND f.loan_term_months <= 180), 0)   AS term_10y_to_15y_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 180 AND f.loan_term_months <= 240) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS term_15y_to_20y_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 180 AND f.loan_term_months <= 240), 0)   AS term_15y_to_20y_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 240 AND f.loan_term_months <= 300) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS term_20y_to_25y_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 240 AND f.loan_term_months <= 300), 0)   AS term_20y_to_25y_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 300 AND f.loan_term_months <= 360) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS term_25y_to_30y_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 300 AND f.loan_term_months <= 360), 0)   AS term_25y_to_30y_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 360) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS term_over_30y_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months > 360), 0)     AS term_over_30y_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months IS NULL) AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS term_not_reported_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND f.loan_term_months IS NULL), 0) AS term_not_reported_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

**The most sharply differentiated table in the section.** Across the market 68.34
percent of originated loans are 25 to 30 years, 647,904 of them exactly 360
months, but individual lenders sit nowhere near that.

Premium Mortgage is 97.64 percent in the 25-to-30-year band and CrossCountry
97.60. Against that, **FOURLEAF writes 80.52 percent of its loans at 15 to 20
years** and **CITIZENS BANK 71.31 percent at 20 to 25 years**, bands holding 7.14
and 6.05 percent of the market. Those are single products written at a single
term, and nothing else on this page makes them visible.

Broadview is the short-term lender: 21.45 percent up to ten years and 42.03
percent from ten to fifteen, so 63.5 percent of its book is fifteen years or
less.

**ESL reports no term on 71.15 percent of its own book**, 16,485 loans. The
not-reported band is kept rather than filtered because across the market those
loans carry 25.6 billion dollars.

The bands are cut at the standard terms rather than on quantiles, because
mortgage terms are not continuous and a quantile cut would have put a boundary
inside the 360-month spike.

### E8. Product Mix by Applicant Age Band

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | age_under_25_loans_pct | age_under_25_loan_amount | age_25_to_34_loans_pct | age_25_to_34_loan_amount | age_35_to_44_loans_pct | age_35_to_44_loan_amount | age_45_to_54_loans_pct | age_45_to_54_loan_amount | age_55_to_64_loans_pct | age_55_to_64_loan_amount | age_65_to_74_loans_pct | age_65_to_74_loan_amount | age_over_74_loans_pct | age_over_74_loan_amount | age_not_provided_loans_pct | age_not_provided_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 1.56 | 169,075,000 | 12.68 | 1,873,285,000 | 21.34 | 3,102,220,000 | 25.32 | 3,388,480,000 | 22.21 | 2,688,500,000 | 12.59 | 1,351,230,000 | 4.30 | 441,580,000 | 0.00 | 0 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 0.65 | 91,460,000 | 12.04 | 2,560,660,000 | 24.71 | 5,166,585,000 | 24.25 | 3,409,300,000 | 21.08 | 2,303,505,000 | 12.16 | 1,106,440,000 | 4.79 | 379,230,000 | 0.33 | 508,150,000 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 4.56 | 730,325,000 | 32.22 | 5,996,800,000 | 29.49 | 6,013,690,000 | 18.47 | 3,678,980,000 | 10.34 | 1,871,695,000 | 3.95 | 637,870,000 | 0.97 | 148,515,000 | 0.00 | 0 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E8">Query E8</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                 AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')               AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)              AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '<25') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS age_under_25_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '<25'), 0)     AS age_under_25_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '25-34') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS age_25_to_34_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '25-34'), 0)     AS age_25_to_34_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '35-44') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS age_35_to_44_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '35-44'), 0)     AS age_35_to_44_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '45-54') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS age_45_to_54_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '45-54'), 0)     AS age_45_to_54_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '55-64') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS age_55_to_64_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '55-64'), 0)     AS age_55_to_64_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '65-74') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS age_65_to_74_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '65-74'), 0)     AS age_65_to_74_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '>74') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)        AS age_over_74_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '>74'), 0)      AS age_over_74_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '8888') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS age_not_provided_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.applicant_age = '8888'), 0) AS age_not_provided_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

**Premium Mortgage has the youngest book**: 6.15 percent under 25 and 40.12
percent at 25 to 34, so 46.3 percent of its loans go to applicants under 35
against a market figure of 23.3. Homestead has the highest under-25 share at
6.32 percent against 2.45.

**ESL has the oldest**: 17.63 percent at 65 to 74 and 6.62 above 74, so 24.3
percent above 65 against a market figure of 10.87. KeyBank is second on both.

**The middle band barely separates lenders at all.** The 35 to 44 band runs 19.67
to 33.25 across the 21 largest, the narrowest range here, while 25 to 34 runs
9.63 to 40.12, a factor of four. Lenders differ in whether they serve first-time
buyers and retirees, not in whether they serve the middle.

JPMorgan reports no age on 7.23 percent of its own book, well ahead of everyone
else, which taken with its 12.01 percent in E5's income-not-reported band is the
same part of its business showing up twice.

### E9. Product Mix by Applicant Sex

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | sex_male_loans_pct | sex_male_loan_amount | sex_female_loans_pct | sex_female_loan_amount | sex_joint_loans_pct | sex_joint_loan_amount | sex_not_available_loans_pct | sex_not_available_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 34.39 | 4,297,370,000 | 23.85 | 2,731,260,000 | 26.37 | 3,925,520,000 | 15.39 | 2,060,220,000 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 35.62 | 5,153,690,000 | 21.87 | 2,203,475,000 | 35.97 | 6,693,950,000 | 6.54 | 1,474,215,000 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 39.30 | 7,608,450,000 | 21.53 | 3,508,275,000 | 34.35 | 7,058,750,000 | 4.82 | 902,400,000 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E9">Query E9</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                  AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)               AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Male') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)            AS sex_male_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Male'), 0)          AS sex_male_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Female') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)          AS sex_female_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Female'), 0)        AS sex_female_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Joint') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)           AS sex_joint_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Joint'), 0)         AS sex_joint_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Sex Not Available') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS sex_not_available_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_sex = 'Sex Not Available'), 0) AS sex_not_available_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

Across the market Joint is the largest category at 35.57 percent of originated
loans, ahead of male at 32.81 and female at 22.12.

**The male-to-female ratio sits in a narrow band across the large lenders and the
joint column is what separates them.** The market ratio is 1.48; Rocket is at
1.44, Citizens 1.63, United Wholesale 1.82. Male runs 28.00 to 39.30 across the
21 largest and female 16.79 to 26.42, both narrow. Joint runs 26.37 to 44.69.

So what distinguishes these lenders is how much of their business is
two-applicant business, which is a statement about the kind of application they
take rather than about applicants. C2a showed joint applications approve 10
points above either individual category, so a lender's joint share also partly
explains its approval rate in E1a.

ROCKET MORTGAGE reports no sex on 15.39 percent of its own book, the highest in
the table and more than six times the lowest.

### E10. Product Mix by Applicant Race

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

*Each share is of that lender's own originated loans, so a row describes its
product mix and sums to 100 across. The amount columns sum to column 4 exactly.*

| lender_name | total_applications | originated_loans | total_loan_amount | race_white_loans_pct | race_white_loan_amount | race_black_loans_pct | race_black_loan_amount | race_asian_loans_pct | race_asian_loan_amount | race_amer_indian_loans_pct | race_amer_indian_loan_amount | race_nhpi_loans_pct | race_nhpi_loan_amount | race_two_or_more_loans_pct | race_two_or_more_loan_amount | race_joint_loans_pct | race_joint_loan_amount | race_free_form_loans_pct | race_free_form_loan_amount | race_not_available_loans_pct | race_not_available_loan_amount |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 63.31 | 7,496,065,000 | 8.72 | 1,275,860,000 | 4.41 | 897,065,000 | 0.39 | 39,980,000 | 0.10 | 12,420,000 | 0.11 | 15,985,000 | 1.33 | 221,250,000 | 0.00 | 0 | 21.62 | 3,055,745,000 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 67.55 | 9,401,095,000 | 6.10 | 527,240,000 | 8.44 | 1,812,415,000 | 0.33 | 34,685,000 | 0.19 | 15,040,000 | 0.13 | 14,805,000 | 2.19 | 573,965,000 | 0.04 | 2,410,000 | 15.04 | 3,143,675,000 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 61.69 | 11,122,180,000 | 7.29 | 1,526,605,000 | 14.31 | 3,196,410,000 | 0.25 | 40,295,000 | 0.12 | 19,505,000 | 0.69 | 173,190,000 | 1.56 | 314,085,000 | 0.00 | 0 | 14.10 | 2,685,605,000 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Union Bank and Trust Company | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |
| Bank of Hawaii | 2 | 0 | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |  | 0 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E10">Query E10</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                   AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                 AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)                AS total_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'White') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)           AS race_white_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'White'), 0)         AS race_white_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Black or African American') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)           AS race_black_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Black or African American'), 0)         AS race_black_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Asian') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)           AS race_asian_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Asian'), 0)         AS race_asian_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'American Indian or Alaska Native') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS race_amer_indian_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'American Indian or Alaska Native'), 0)   AS race_amer_indian_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Native Hawaiian or Other Pacific Islander') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)            AS race_nhpi_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Native Hawaiian or Other Pacific Islander'), 0)          AS race_nhpi_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = '2 or more minority races') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)     AS race_two_or_more_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = '2 or more minority races'), 0)   AS race_two_or_more_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Joint') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)           AS race_joint_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Joint'), 0)         AS race_joint_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Free Form Text Only') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)       AS race_free_form_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Free Form Text Only'), 0)     AS race_free_form_loan_amount,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Race Not Available') AS DECIMAL(24,8))
             / CAST(NULLIF(count(*) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,8)), 2)   AS race_not_available_loans_pct,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1' AND a.derived_race = 'Race Not Available'), 0) AS race_not_available_loan_amount
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

**The Asian column separates lenders more than any other.** JPMorgan is at 21.29
percent of its own book and Citibank 19.71, against a market figure of 9.15 and a
low of 1.08 across the 21 largest, a factor of twenty. Both are concentrated in
New York City, which C1b and A7 already established is where that difference
largely comes from.

The White column runs 50.46 to 86.26, highest at Community Bank and Empower, both
upstate lenders. The Black column runs 2.34 to 8.72, highest at Rocket and Bank
of America.

**Race not reported is as variable as any named category**, 5.93 to 26.52, with
loanDepot highest. For a lender taking applications online the race field is more
often left blank, so the column is partly measuring channel.

**A fairness reading is not available from this table and is not meant to be.**
These are proportions of each lender's own book, so a cell says what share of
that lender's lending went to a group, not whether that group was treated
differently. That is a rate question, answered in
[C1a](#c1a-applications-and-outcomes-by-applicant-race) and
[D4](#d4-denial-reason-by-applicant-race) with each group's own applications in
the denominator.

### E11. Geographic Reach

*All 1,139 lenders are returned. The table shows the three largest and the three
smallest; the run-live link returns the complete result and lets you re-sort it.
Figures quoted in the reading below come from the full result, not only from the
six rows printed here.*

| lender_name | total_applications | originated_loans | total_loan_amount | census_tracts | tract_coverage_pct | loans_per_tract |
|---|---|---|---|---|---|---|
| ROCKET MORTGAGE | 77,402 | 49,930 | 13,014,370,000 | 4,534 | 85.85 | 11.0 |
| CITIZENS BANK, NA | 82,894 | 43,046 | 15,525,330,000 | 4,629 | 87.65 | 9.3 |
| United Wholesale Mortgage | 56,090 | 42,059 | 19,077,875,000 | 4,460 | 84.45 | 9.4 |
| &#8942; &nbsp;*1,133 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| Bank of the West (San Francisco, CA) | 1 | 0 | 0 | 0 | 0.00 |  |
| Union Bank and Trust Company | 2 | 0 | 0 | 0 | 0.00 |  |
| Bank of Hawaii | 2 | 0 | 0 | 0 | 0.00 |  |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=E11">Query E11</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']'
                ELSE label
           END AS lender_name
    FROM (SELECT lei,
                 label,
                 count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name
                       END AS label
                FROM (SELECT lei,
                             institution_name,
                             institution_city,
                             institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei,
                                   i.institution_name,
                                   i.institution_city,
                                   i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                            AS total_applications,
       count(*) FILTER (WHERE f.action_taken = '1')                         AS originated_loans,
       COALESCE(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0)  AS total_loan_amount,
       count(DISTINCT CASE WHEN f.action_taken = '1' AND f.census_tract <> 'UNKNOWN'
                           THEN f.census_tract END)                         AS census_tracts,
       round(CAST(100.0 * count(DISTINCT CASE WHEN f.action_taken = '1' AND f.census_tract <> 'UNKNOWN'
                                              THEN f.census_tract END) AS DECIMAL(24,8))
             / CAST((SELECT count(DISTINCT census_tract)
                     FROM marts.fct_application
                     WHERE census_tract <> 'UNKNOWN') AS DECIMAL(24,8)), 2) AS tract_coverage_pct,
       round(CAST(count(*) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / CAST(NULLIF(count(DISTINCT CASE WHEN f.action_taken = '1' AND f.census_tract <> 'UNKNOWN'
                                               THEN f.census_tract END), 0) AS DECIMAL(24,4)), 1)
                                                                           AS loans_per_tract
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
WHERE f.action_taken <> '6'
GROUP BY l.lei, l.lender_name
ORDER BY 3 DESC, l.lei;
```

</details>

A3 counts 5,281 census tracts in the New York data, which is the figure a
lender's count is read against. A tract is a neighbourhood of a few thousand
people.

**Only four lenders reach more than 80 percent of the state's tracts**: Citizens
at 87.65 percent, Rocket 85.85, United Wholesale 84.45 and JPMorgan 83.73. Nobody
else exceeds 73 percent. Thirteen lenders out of 1,139 reach half the state; 791
reach less than a tenth; 181 lend in exactly one tract.

**The two right-hand columns separate two business models the volume columns
hide.** ESL made 23,170 originated loans, more than Wells Fargo or Bank of
America, in **397 tracts, 7.52 percent of the state, at 58.4 loans per tract**.
CrossCountry and Bank of America both run at **4.8 loans per tract** across about
70 percent of it. Among lenders above 10,000 originations the figure runs from
3.2 to 58.4, a factor of eighteen. A high figure is a regional lender dense in
its own territory, a low one a statewide originator thin everywhere, and neither
is better.

'UNKNOWN' is excluded from both the numerator and the denominator. 3,373
originated loans across 67 lenders carry it, and counting it would hand each of
those lenders a tract that does not exist.

</details>

---

## F. Recommendations

<details>
<summary><b>Four queries, then what they support for applicants, lenders and communities</b></summary>

**What a recommendation from this register can be, and what it cannot.** HMDA
holds no credit score. It records what lenders decided and what they wrote down
as the reason, not what the lender saw. So nothing in this section establishes
that changing a number changes an outcome. Every recommendation below is of one
form: *applications with this characteristic were decided this way*, and the
reader supplies the rest. That is a weaker claim than "do this and you will be
approved", and it is the only claim the data supports.

Where a recommendation rests on something other than a measurement here, it is
labelled as such rather than dressed up.

### F1. Outcome by Debt to Income Band

| dti_band | total_applications | share_of_applications | approval_rate | denial_rate | incomplete_rate | withdrawal_rate |
|---|---|---|---|---|---|---|
| Under 20% | 74,303 | 4.65 | 75.51 | 24.49 | 0.00 | 0.00 |
| 20% to under 30% | 175,619 | 11.00 | 86.11 | 13.89 | 0.00 | 0.00 |
| 30% to under 36% | 168,500 | 10.55 | 86.87 | 13.13 | 0.00 | 0.00 |
| 36% to 39% | 138,769 | 8.69 | 86.82 | 13.18 | 0.00 | 0.00 |
| 40% to 44% | 208,512 | 13.06 | 86.55 | 13.45 | 0.00 | 0.00 |
| 45% to 49% | 194,950 | 12.21 | 84.95 | 15.05 | 0.00 | 0.00 |
| 50% to 60% | 114,329 | 7.16 | 59.14 | 40.86 | 0.00 | 0.00 |
| Over 60% | 114,312 | 7.16 | 9.58 | 90.42 | 0.00 | 0.00 |
| Not reported | 407,382 | 25.51 | 25.70 | 7.44 | 19.27 | 47.59 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=F1">Query F1</a></summary>

```sql
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
```

</details>

**The strongest single relationship in the project, and a cliff rather than a
slope.** The five bands from 20 to 49 percent cover 55.5 percent of all
applications and sit within 1.92 points of each other. Then 50 to 60 denies at
40.86 percent and above 60 at 90.42.

**Below 20 percent the rate rises again**, to 24.49. That bottom is not
conservative borrowers, it is small second-lien business, which
[F2](#f2-outcome-by-loan-to-income-and-loan-to-value-home-purchase-first-liens)
separates out.

**The not-reported row is a stage, not a ratio.** A quarter of the register,
denying at 7.44 percent but withdrawing at 47.59 and going incomplete at 19.27.
The ratio is computed during underwriting, so these mostly never reached it. It
is the largest loss of applications in the data and none of it is a credit
decision.

HMDA files this field as a band outside 36 to 49 percent and as an exact integer
inside it, which is what the query normalises.

### F2. Outcome by Loan to Income and Loan to Value, Home Purchase First Liens

| measure | band | total_applications | share_of_applications | approval_rate | denial_rate |
|---|---|---|---|---|---|
| loan to income | under 2.0 | 198,886 | 27.84 | 73.96 | 9.83 |
| loan to income | 2.0 to under 3.0 | 196,876 | 27.56 | 77.38 | 7.49 |
| loan to income | 3.0 to under 4.0 | 142,436 | 19.94 | 76.14 | 8.34 |
| loan to income | 4.0 to under 5.0 | 72,450 | 10.14 | 73.07 | 10.67 |
| loan to income | 5.0 to under 6.0 | 25,120 | 3.52 | 65.23 | 17.82 |
| loan to income | 6.0 and over | 18,271 | 2.56 | 48.06 | 33.56 |
| loan to income | income not reported | 60,326 | 8.44 | 67.11 | 14.07 |
| loan to value | up to 70% | 130,701 | 18.30 | 90.20 | 9.80 |
| loan to value | over 70% to 80% | 189,430 | 26.52 | 90.34 | 9.66 |
| loan to value | over 80% to 90% | 80,540 | 11.27 | 89.16 | 10.84 |
| loan to value | over 90% to 95% | 68,749 | 9.62 | 89.14 | 10.86 |
| loan to value | over 95% to 100% | 81,661 | 11.43 | 86.44 | 13.56 |
| loan to value | over 100% | 8,158 | 1.14 | 69.17 | 30.83 |
| loan to value | ratio not reported | 155,126 | 21.72 | 18.14 | 7.82 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=F2">Query F2</a></summary>

```sql
WITH purchase AS (
    SELECT f.action_taken,
           CASE WHEN f.income_thousands IS NULL OR f.income_thousands <= 0        THEN 9
                WHEN f.loan_amount / (f.income_thousands * 1000) <  2             THEN 1
                WHEN f.loan_amount / (f.income_thousands * 1000) <  3             THEN 2
                WHEN f.loan_amount / (f.income_thousands * 1000) <  4             THEN 3
                WHEN f.loan_amount / (f.income_thousands * 1000) <  5             THEN 4
                WHEN f.loan_amount / (f.income_thousands * 1000) <  6             THEN 5
                ELSE 6
           END AS lti_key,
           CASE WHEN f.loan_to_value_ratio IS NULL                                THEN 9
                WHEN f.loan_to_value_ratio <=  70                                 THEN 1
                WHEN f.loan_to_value_ratio <=  80                                 THEN 2
                WHEN f.loan_to_value_ratio <=  90                                 THEN 3
                WHEN f.loan_to_value_ratio <=  95                                 THEN 4
                WHEN f.loan_to_value_ratio <= 100                                 THEN 5
                ELSE 6
           END AS ltv_key
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
      AND p.loan_purpose = '1'
      AND p.lien_status  = '1'
),
lti_label (band_key, band) AS (
    VALUES (1, 'under 2.0'), (2, '2.0 to under 3.0'), (3, '3.0 to under 4.0'),
           (4, '4.0 to under 5.0'), (5, '5.0 to under 6.0'), (6, '6.0 and over'),
           (9, 'income not reported')
),
ltv_label (band_key, band) AS (
    VALUES (1, 'up to 70%'), (2, 'over 70% to 80%'), (3, 'over 80% to 90%'),
           (4, 'over 90% to 95%'), (5, 'over 95% to 100%'), (6, 'over 100%'),
           (9, 'ratio not reported')
),
lti AS (
    SELECT 1 AS measure_order, 'loan to income' AS measure, p.lti_key AS band_key,
           count(*) AS total_applications,
           count(*) FILTER (WHERE p.action_taken IN ('1','2','8')) AS approved,
           count(*) FILTER (WHERE p.action_taken IN ('3','7'))     AS denied
    FROM purchase p GROUP BY 1, 2, 3
),
ltv AS (
    SELECT 2 AS measure_order, 'loan to value' AS measure, p.ltv_key AS band_key,
           count(*) AS total_applications,
           count(*) FILTER (WHERE p.action_taken IN ('1','2','8')) AS approved,
           count(*) FILTER (WHERE p.action_taken IN ('3','7'))     AS denied
    FROM purchase p GROUP BY 1, 2, 3
),
combined AS (
    SELECT l.measure_order, l.measure, lab.band, l.band_key, l.total_applications, l.approved, l.denied
    FROM lti l JOIN lti_label lab ON lab.band_key = l.band_key
    UNION ALL
    SELECT v.measure_order, v.measure, lab.band, v.band_key, v.total_applications, v.approved, v.denied
    FROM ltv v JOIN ltv_label lab ON lab.band_key = v.band_key
)
SELECT measure,
       band,
       total_applications,
       round(CAST(100.0 * total_applications AS DECIMAL(24,8))
             / CAST(sum(total_applications) OVER (PARTITION BY measure) AS DECIMAL(24,8)), 2)
                                                                        AS share_of_applications,
       round(CAST(100.0 * approved AS DECIMAL(24,8))
             / CAST(total_applications AS DECIMAL(24,8)), 2)            AS approval_rate,
       round(CAST(100.0 * denied AS DECIMAL(24,8))
             / CAST(total_applications AS DECIMAL(24,8)), 2)            AS denial_rate
FROM combined
ORDER BY measure_order, band_key;
```

</details>

**The restriction is the point of this query.** Across the whole register both
ratios appear to reward lower values and then contradict themselves: under one
times income denies at 25.55 percent against 14.37 at two to three. That is the
product, not the borrower. Those applications are **70.6 percent
subordinate-lien and 66.4 percent home improvement or other purpose**, purposes
[D3](#d3-denial-reason-by-loan-purpose) put at 35 percent. Holding purpose and
lien constant removes it.

**Both ratios are flat and then steep, and the threshold is the finding.** Loan
to income stays within 2.3 points out to four times income, then reaches 33.56
above six. Loan to value moves 3.8 points out to 95 percent, then trebles above
100.

### F3. Lender Outcomes on One Product

*All 72 lenders with 2,000 or more such applications are returned, ordered by
denial rate. The table shows the five lowest and the five highest; the run-live
link returns the complete result. Figures quoted below come from the full 72,
not only from the ten rows printed here.*

| lender_name | total_applications | approval_rate | denial_rate | median_loan_to_value | median_loan_to_income | median_applicant_income |
|---|---|---|---|---|---|---|
| SEFCU Services, LLC | 10,639 | 90.76 | 1.14 | 90.00 | 2.41 | 110,000 |
| FIRST REPUBLIC BANK | 4,539 | 84.84 | 1.52 | 75.00 | 2.60 | 304,000 |
| Lyons National Bank | 2,560 | 92.97 | 1.64 | 80.00 | 2.02 | 110,000 |
| Premium Mortgage Corporation | 16,996 | 90.47 | 1.88 | 80.00 | 2.18 | 103,000 |
| Homestead Funding Corp. | 14,418 | 83.70 | 1.88 | 85.07 | 2.30 | 110,000 |
| &#8942; &nbsp;*62 lenders skipped*&nbsp; &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; | &#8942; |
| HomeBridge Financial Services, Inc | 3,170 | 73.38 | 24.20 | 80.00 | 3.28 | 142,000 |
| Flagstar Bank NA | 2,708 | 59.31 | 31.57 | 80.00 | 2.72 | 138,000 |
| 21ST MORTGAGE | 7,552 | 20.83 | 45.26 |  | 1.67 | 60,000 |
| TRIAD FINANCIAL SERVICES, INC. | 4,386 | 54.45 | 45.30 |  | 1.34 | 59,000 |
| Credit Human Federal Credit Un | 2,699 | 48.35 | 51.39 | 94.99 | 1.34 | 64,000 |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=F3">Query F3</a></summary>

```sql
WITH lender AS (
    SELECT lei,
           CASE WHEN label_holders > 1 THEN label || ' [' || lei || ']' ELSE label END AS lender_name
    FROM (SELECT lei, label, count(*) OVER (PARTITION BY label) AS label_holders
          FROM (SELECT lei,
                       CASE WHEN name_holders > 1
                            THEN institution_name || ' (' || institution_city || ', ' || institution_state || ')'
                            ELSE institution_name END AS label
                FROM (SELECT lei, institution_name, institution_city, institution_state,
                             count(*) OVER (PARTITION BY institution_name) AS name_holders
                      FROM (SELECT i.lei, i.institution_name, i.institution_city, i.institution_state,
                                   row_number() OVER (PARTITION BY i.lei
                                                      ORDER BY i.activity_year DESC, i.institution_name) AS name_rank
                            FROM marts.dim_institution i) ranked
                      WHERE name_rank = 1) named) labelled) unique_label
)
SELECT l.lender_name,
       count(*)                                                            AS total_applications,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('1','2','8')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS approval_rate,
       round(CAST(100.0 * count(*) FILTER (WHERE f.action_taken IN ('3','7')) AS DECIMAL(24,8))
             / CAST(count(*) AS DECIMAL(24,8)), 2)                          AS denial_rate,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2','3','7','8')
                            THEN f.loan_to_value_ratio END)
             AS DECIMAL(24,8)), 2)                                         AS median_loan_to_value,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2','3','7','8') AND f.income_thousands > 0
                            THEN f.loan_amount / (f.income_thousands * 1000) END)
             AS DECIMAL(24,8)), 2)                                         AS median_loan_to_income,
       round(CAST(percentile_disc(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2','3','7','8') AND f.income_thousands > 0
                            THEN f.income_thousands * 1000 END)
             AS DECIMAL(24,8)))                                            AS median_applicant_income
FROM marts.fct_application f
JOIN lender l ON l.lei = f.lei
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
WHERE f.action_taken <> '6'
  AND p.loan_purpose = '1'
  AND p.lien_status  = '1'
  AND p.loan_type    = '1'
GROUP BY l.lei, l.lender_name
HAVING count(*) >= 2000
ORDER BY denial_rate, l.lei;
```

</details>

**[E1a](#e1a-lender-outcomes-and-market-share)'s lender spread was mostly
product mix. This is what is left when the mix is removed.** Same product in
every row, for the 72 lenders with 2,000 or more such applications. The range
narrows to 1.14 to 31.57 percent excluding the three manufactured-housing
lenders at the bottom, whose collateral is a different class. The median is 7.58.

**Columns 5 to 7 kill the obvious objection, that low-denial lenders simply
receive stronger applications.**

| lender | applications | median LTV | median LTI | median income | denial rate |
|---|---|---|---|---|---|
| SEFCU Services, LLC | 10,639 | **90.00** | 2.41 | **110,000** | **1.14** |
| Bank of America NA | 11,600 | 80.00 | 2.58 | 179,000 | **17.76** |

SEFCU's applicants are more leveraged and earn substantially less, and it denies
them 15.6 times less often. Not causal: there is no credit score here, so this
establishes the size of the stakes rather than the mechanism.

### F4. How Much Choice a Borrower Has, by Purpose

| purpose | total_applications | market_denial_rate | lenders_active | lenders_rankable | p10_lender_denial_rate | median_lender_denial_rate | p90_lender_denial_rate |
|---|---|---|---|---|---|---|---|
| Home purchase | 733,126 | 10.78 | 934 | 191 | 3.05 | 8.27 | 24.33 |
| Home improvement | 247,663 | 35.13 | 493 | 59 | 10.36 | 26.11 | 47.51 |
| Cash-out refinancing | 231,963 | 19.89 | 625 | 86 | 3.95 | 13.94 | 33.17 |
| Other purpose | 195,592 | 35.84 | 479 | 54 | 12.20 | 31.88 | 51.49 |
| Refinancing | 188,094 | 20.45 | 694 | 68 | 3.47 | 17.15 | 34.92 |
| Not applicable | 238 | 14.71 | 36 | 0 |  |  |  |

<details>
<summary>View SQL Query&nbsp; &middot; &nbsp;Run live <a href="https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=F4">Query F4</a></summary>

```sql
WITH by_lender AS (
    SELECT p.loan_purpose,
           f.lei,
           count(*)                                                AS apps,
           count(*) FILTER (WHERE f.action_taken IN ('3','7'))      AS denied
    FROM marts.fct_application f
    JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
    WHERE f.action_taken <> '6'
    GROUP BY 1, 2
),
rate AS (
    SELECT loan_purpose, lei, apps, denied,
           CAST(100.0 * denied AS DECIMAL(24,8)) / CAST(apps AS DECIMAL(24,8)) AS denial_rate
    FROM by_lender
),
purpose_label (loan_purpose, purpose) AS (
    VALUES ('1',  'Home purchase'),   ('31', 'Refinancing'),
           ('32', 'Cash-out refinancing'), ('2',  'Home improvement'),
           ('4',  'Other purpose'),   ('5',  'Not applicable')
)
SELECT l.purpose,
       sum(r.apps)                                                        AS total_applications,
       round(CAST(100.0 * sum(r.denied) AS DECIMAL(24,8))
             / CAST(sum(r.apps) AS DECIMAL(24,8)), 2)                     AS market_denial_rate,
       count(*)                                                           AS lenders_active,
       count(*) FILTER (WHERE r.apps >= 500)                              AS lenders_rankable,
       round(CAST(percentile_disc(0.10) WITHIN GROUP (
              ORDER BY CASE WHEN r.apps >= 500 THEN r.denial_rate END) AS DECIMAL(24,8)), 2)
                                                                          AS p10_lender_denial_rate,
       round(CAST(percentile_disc(0.50) WITHIN GROUP (
              ORDER BY CASE WHEN r.apps >= 500 THEN r.denial_rate END) AS DECIMAL(24,8)), 2)
                                                                          AS median_lender_denial_rate,
       round(CAST(percentile_disc(0.90) WITHIN GROUP (
              ORDER BY CASE WHEN r.apps >= 500 THEN r.denial_rate END) AS DECIMAL(24,8)), 2)
                                                                          AS p90_lender_denial_rate
FROM rate r
JOIN purpose_label l ON l.loan_purpose = r.loan_purpose
GROUP BY l.purpose
ORDER BY 2 DESC;
```

</details>

**Choice exists, it is worth a great deal, and both vary sharply by purpose.**
For home purchase 934 lenders took an application and 191 took at least 500, and
across those 191 the tenth and ninetieth percentiles are 3.05 and 24.33 percent.
For home improvement only 493 took an application and 59 took 500. **A homeowner
borrowing against a house they already own faces a market three times harder
than a buyer, with half as many lenders in it.**

**The median lender is more generous than the market on every purpose**, because
the market rate is weighted by volume and the largest lenders deny more often.

The percentiles are over lenders rather than applications, so one lender is one
observation regardless of size.


### The Recommendations

#### For Applicants

**1. Keep total debt service under 50 percent of income, and stop optimising
below 20.** This is the only hard threshold in the register. From 20 to 49
percent the denial rate sits between 13.13 and 15.05. At 50 to 60 it is 40.86.
Above 60 it is 90.42. The practical form is a line, not a direction: get under
50, and there is no measured benefit to going under 20.
Evidence: [F1](#f1-outcome-by-debt-to-income-band), the strongest in the
section, 1.19 million applications with a reported band.

**2. Borrowing up to four times income carries no measurable penalty. Above five
times it does.** On purchase applications, under two times income denies at 9.83,
two to three at 7.49, three to four at 8.34. Five to six is 17.82 and above six
is 33.56.
Evidence: [F2](#f2-outcome-by-loan-to-income-and-loan-to-value-home-purchase-first-liens).

**3. Leverage matters less than most people expect, until it passes 100
percent.** Up to 95 percent of value the denial rate moves 1.2 points. Above 100
percent it triples.
Evidence: [F2](#f2-outcome-by-loan-to-income-and-loan-to-value-home-purchase-first-liens).

**4. Finish the application. More applications are lost to abandonment than to
refusal in some books.** 407,382 applications, a quarter of the register, have no
debt-to-income band at all, with 47.59 percent withdrawal and 19.27 percent
incompleteness: they ended before underwriting. At the lender level NEWREZ ends
41.52 percent of its applications with no decision either way and DISCOVER BANK
leaves 28.55 percent incomplete, against market figures of 12.14 and 4.92.
Evidence: [F1](#f1-outcome-by-debt-to-income-band) and
[E1a](#e1a-lender-outcomes-and-market-share). The most overlooked item here,
because it is not about creditworthiness at all.

**5. Apply to more than one lender, and pick ones that write your product.** On
the same product, lien and purpose, denial rates across the 72 largest lenders
run from 1.14 to 31.57 percent, and one lender denies 15.6 times less often than
another while taking more leveraged applications from lower earners. The median
tract has 44 lenders active in it.
Evidence: [F3](#f3-lender-outcomes-on-one-product),
[F4](#f4-how-much-choice-a-borrower-has-by-purpose) and
[E11](#e11-geographic-reach).

**6. If you are borrowing against a home you already own rather than buying,
expect a harder market and start earlier.** Home improvement and other purpose
deny at 35.13 and 35.84 percent against 10.78 for purchase, with roughly half as
many lenders active.
Evidence: [F4](#f4-how-much-choice-a-borrower-has-by-purpose) and
[D3](#d3-denial-reason-by-loan-purpose).

**7. Credit history matters, and this is the weakest-evidenced item here.** It is
cited on 21.71 percent of all denials, second only to debt-to-income. But HMDA
holds no credit score, so the register shows how often lenders wrote it down,
not how much improving it would change an outcome. It belongs in the list because
it is the second most common reason a lender gives; it does not belong with the
first three, which are measured against outcomes.
Evidence: [Section D](#d-mortgage-denial-analysis), as citation frequency rather
than effect.

#### For Lenders

All process and reporting observations. None touches an applicant
characteristic, protected or otherwise.

**1. Applications that end without a decision are a measurable, controllable
loss.** Across the market 12.14 percent of applications are withdrawn and 4.92
percent go incomplete. CROSSCOUNTRY MORTGAGE withdraws 25.56 percent, NEWREZ
loses 41.52 percent to the two combined, DISCOVER BANK leaves 28.55 percent
incomplete. Those are applications a lender paid to acquire and then lost without
making a credit decision, and the spread between lenders on that measure is
wider than the spread on denial.
Evidence: [E1a](#e1a-lender-outcomes-and-market-share).

**2. Filing quality is uneven in ways visible from outside.** Three lenders with
more than 1,000 originated loans report no interest rate on any of them. Pioneer
Bank reports one rate across 1,071 loans. 144 lenders file originated loans with
no loan amount. ESL reports no loan term on 71.15 percent of its own book. 1,279
LEIs file more than one spelling of their own name across four years. For a
bureau or a supervisor these are audit findings available from the public file
alone.
Evidence: [E4](#e4-product-mix-by-loan-amount-band),
[E6](#e6-interest-rate-distribution) and [E7](#e7-product-mix-by-loan-term).

**3. Single-product concentration is visible and worth measuring in your own
book.** CITIZENS BANK writes 71.31 percent of its loans at one term band holding
6.05 percent of the market. FOURLEAF writes 80.52 percent at another holding
7.14. ESL lends in 7.52 percent of the state's census tracts at 58.4 loans per
tract. None of that is a criticism; all of it is concentration a risk function
would want measured rather than inferred.
Evidence: [E7](#e7-product-mix-by-loan-term) and
[E11](#e11-geographic-reach).

**4. A denial reason mix that differs from the market is a prompt to check the
process, not the applicants.** Insufficient cash is cited 2.55 times as often on
FHA as on conventional lending and credit application incomplete 1.90 times as
often, which is a documentation and hand-holding difference rather than a credit
one.
Evidence: [D2](#d2-denial-reason-by-loan-type).

#### For Communities and for Anyone Teaching This

**1. The 50 percent debt-to-income line is the single most teachable fact in the
register, and it is not what people are usually told.** The common advice is to
keep debt as low as possible. The data says there is a flat zone from 20 to 49
percent where the denial rate barely moves, a cliff at 50 and a wall at 60. That
replaces vague advice with a number.

**2. Lower is not always better, and the reason is worth teaching too.** The raw
figures appear to reward very low ratios until you notice that very low ratios
are mostly a different product. That is a lesson about reading data as much as
about mortgages, and it is the clearest worked example of confounding on this
page.

**3. Choice is real, large and invisible.** The median neighbourhood has 44
lenders originating in it, and on identical products the gap between a generous
and a strict one is an order of magnitude. Most borrowers approach one lender.

**4. Not finishing is a bigger risk than being refused.** A quarter of all
applications never reached underwriting. Teaching people what documents will be
asked for, and when, addresses a larger share of lost applications than anything
to do with credit quality.

**5. If you are borrowing against a home you own, the market is a different
place.** Three times the denial rate, half the lenders, and a reason mix leaning
to credit history rather than to cash.

</details>

---

## The Data Model

<details>
<summary><b>99 flat columns modelled into 17 tables and 175 documented columns</b></summary>

The published HMDA Loan Application Register is one flat file of 99 columns. It
is modelled here into a dimensional warehouse of 17 tables across two schemas.

`marts` holds the analytical model: a fact table partitioned by `activity_year`,
eight dimensions, four bridge tables and a quarantine table. `ref` holds the
reference data: the code-to-label lookups the regulator publishes, the vintage
record for each filing year, and the assertion catalogue.

**`marts.fct_application`** is the grain of the whole model: one row per
application, 1,755,419 of them across four years, of which 1,596,676 remain once
purchased loans are excluded. It carries 41 columns.

**The eight dimensions** are `dim_applicant_profile` (4,745 rows),
`dim_loan_product` (194), `dim_dwelling` (41), `dim_institution` (19,321),
`dim_county` (255), `dim_tract` (20,820), `dim_msa` (1,666) and `dim_date` (4).
`dim_loan_product` and `dim_dwelling` are junk dimensions: they collapse seven
and four coded attributes respectively into the combinations that actually
occur, which is why a loan's type, purpose, lien status and reverse-mortgage
flag resolve through one surrogate key rather than four joins.

**The four bridge tables** carry the one-to-many parts the flat file folds into
repeated columns, which is the modelling decision the register most obviously
demands and most obviously resists. `br_denial_reason` holds up to four denial
reasons per application, 438,591 rows, which is why
[Section D](#d-mortgage-denial-analysis) counts citations rather than
applications. `br_application_race` does the same for the up-to-five race fields
for both applicant and co-applicant, 3,662,829 rows.
`br_application_ethnicity` and `br_underwriting_system` complete the set.

**`marts.quarantine_application`** holds 573 rows that failed a validation rule,
each stored with the rule it broke rather than silently dropped.

**`ref.ref_code`** carries the regulator's 450 code-to-label mappings, which is
why no query on this page writes a label like 'Home purchase' into a `CASE`
statement. **`ref.ref_source_vintage`** records which published file each year
came from and when it was frozen, which is what
[Section B](#b-mortgage-market-trends-year-on-year) relies on when it says the
four years are not equally complete. **`ref.assertion_catalog`** holds the
quality rules and their thresholds.

The register carries county FIPS codes and no county names at all, and there is
no county-name reference table here. The 62 names are supplied inline in
[A6](#a6-the-ten-most-expensive-census-tracts) and
[A7](#a7-the-ten-most-expensive-counties) as a `VALUES` list, which keeps those
queries runnable anywhere the fact table is and puts the mapping in front of the
reader rather than behind a join. All 62 codes match, which is also the check
that restricting to codes beginning 36 captures the whole state.

**The browser gets 40 of the fact table's 41 columns.** `row_hash`, the
`md5(row::text)` key the surrogate keys and the uniqueness assertion are built
on, was 42 percent of the Parquet export: 30.5 MB of hex digest that no query
can read. Holding it back took the download from 82.0 MiB to 52.9 MiB and
changed no published figure. Every analytical column is still there, including
the ones no query on this page uses.

The **[data dictionary](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/catalog/)** documents all 175 columns and is
generated from the database catalog at build time rather than written by hand,
so it cannot drift from the schema. The **[ERD](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/erd/)** shows the table
relationships.

</details>

---

## Where the Data Comes From

<details>
<summary><b>FFIEC HMDA Loan Application Register, New York State, 2022 to 2025</b></summary>

Federal Financial Institutions Examination Council, Home Mortgage Disclosure Act
Loan Application Register, filtered to New York State, filing years 2022 to
2025. The data is public and is published annually under the Home Mortgage
Disclosure Act, which requires most mortgage lenders to report every application
they receive.

**The four years are not equally complete.** 2022 is a three-year file, 2023 and
2024 are one-year files, and 2025 is the provisional vintage published before
the final one. **No trend claim on this page rests on 2025 alone.**

**What the register contains**: the lender, the property's census tract and
county, the loan's type, purpose, lien position, amount and term, the applicant's
reported income, race, ethnicity, sex and age band, the action the lender took,
and, where the lender refused, up to four reasons.

**What it does not contain, and this governs everything above**: no credit
score, no assets, no employment record, no down payment source, no loan file. A
lender decides on all of those and reports none of them. So this register
supports statements about what happened and does not support statements about
why.

</details>

---

## How the Numbers Are Checked

<details>
<summary><b>Forty-two queries verified to return identical results in PostgreSQL and DuckDB</b></summary>

**Every query runs in two engines and the results are compared row by row.** The
analysis is developed against PostgreSQL and the browser playground runs DuckDB
over a Parquet export of the same data. An automated parity test runs all
forty-two queries in both and fails if any cell differs.

That test has changed published figures twice, and neither difference raised an
error in either engine.

**A median interest rate interpolated between two loans** on an even-sized group
of 288, and the two engines landed either side of the third decimal: 6.657
against 6.656. The fix was `percentile_disc` rather than `percentile_cont`, which
returns a rate a borrower actually paid instead of a midpoint between two of
them. Every median on this page now uses it.

**`NUMERIC` is not the same type in the two engines.** In DuckDB it is an alias
for `DECIMAL(18,3)`, three decimal places; in PostgreSQL it is arbitrary
precision. So `round(CAST(x AS numeric), 2)` rounds twice in one engine and once
in the other, and a value with a 5 in the third decimal comes out differently:
17.154582763337893 became 17.155 and then 17.16, against 17.15. Four figures on
this page were affected. All sixty-one casts in these queries now name the
precision, `CAST(x AS DECIMAL(24,8))`, which means the same thing in both. The
general lesson is that an unqualified type name is not a portable type.

**Exact decimal arithmetic, with the precision stated.** Every percentage casts
to `DECIMAL(24,8)` before dividing, and every median casts to `DECIMAL(24,8)`
before rounding. Floating-point division produces engine-specific results in the
last place, and an unqualified `numeric` is three decimal places in one of the
two engines, which is exactly what a parity test catches and exactly what a
reader should not have to think about.

**Row order is determined, not left to the engine.** `ORDER BY` on a text column
depends on the collation: PostgreSQL uses the database collation, DuckDB sorts
by bytes. Where a sort can tie, which in Section E is hundreds of lenders on a
single application, the tiebreaker is the LEI rather than the lender's name,
because an LEI is twenty characters of `[A-Z0-9]` and sorts the same under any
collation. Every query was then checked for order stability by running it at one
thread and at eight, which changes the scan order into the sort: all forty-two
return an identical row order.

**Every table reconciles to A1.** Sections A, C, D, E and F each sum to 1,596,676
applications, 951,371 originated loans and 371,417,740,000 dollars where the
query covers the whole population. Several cross-check further: E5's eight column
sums reproduce C4a's originated share column, E8's reproduce C3b's concentration
table, E9's reproduce C2a's and E10's reproduce C1a's, each from a query grouped
on something entirely different.

**573 rows are quarantined, not dropped.** Each failed a validation rule and is
stored with the rule it broke, so the exclusions are auditable rather than
invisible.

**The limitations are stated where they bite, not in a footnote.** No credit
score, so nothing is causal. Four years pooled across a 237.5 basis point rate
move, so every pooled median rate is read against
[B2](#b2-the-typical-loan-that-was-made-by-year). Product mix differs by lender
and by group, so the tables that need it hold product constant and say so.

</details>

---

## Three Things This Repository Does Differently

<details>
<summary><b>Every query runs in your browser, every column is documented from the catalog, every figure reconciles</b></summary>

**The analysis is executable, not illustrated.** 1.75 million rows run in the
browser over WebAssembly. There is no install, no account and nothing sent to a
server. Every query on this page has a Run live link that opens the playground
with that query loaded and already executed, so a reader can change a line and
see what happens.

**The documentation is generated, not written.** The data dictionary's 175
columns come from the database catalog at build time. A column renamed in a
migration appears renamed in the dictionary without anyone remembering to do it.

**The numbers check each other.** Forty-two queries, two engines, one set of
totals. Where a figure appears twice it is computed twice, by different queries
grouped on different things, and the two are compared.

</details>

---

## Author

Samuel Babajide — Data Scientist specialising in applied analytics and predictive
modelling within complex, regulated environments.

[Website](https://samuelbabajide.github.io/) · [LinkedIn](https://www.linkedin.com/in/samuelbbabajide)
