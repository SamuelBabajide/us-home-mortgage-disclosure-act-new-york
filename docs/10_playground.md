# Phase 10: The browser playground

The problem this project started from: a SQL portfolio on GitHub is a folder of `.sql` files that nobody can run. This phase makes the database itself openable in a browser tab, with the published queries returning the published numbers.

Previous phase: [09 Performance tuning](09_performance_tuning.md) · Back to [the README](../README.md)

---

## 1. What a reviewer can actually do

Open the page. After the load described in section 5, there is a dropdown with the forty-two published queries, an editable SQL box, and 1,754,846 rows of real mortgage data in sixteen tables and three labelled views. Every query runs inside the tab. Nothing is installed, no account exists, no data leaves the machine, and there is no server to keep running or pay for.

Measured on the built site, all ten published queries:

| query | rows | time |
|---|---|---|
| 01 denial by year | 4 | 99 ms |
| 02 outcome mix | 8 | 215 ms |
| 03 denial by group | 9 | 145 ms |
| 04 gap within income | 5 | 198 ms |
| 05 shift share | 1 | 387 ms |
| 06 within tract | 1 | 819 ms |
| 07 lender spread | 1 | 593 ms |
| 08 race rollup trap | 1 | 1,618 ms |
| 09 incompleteness channel | 21 | 335 ms |
| 10 reconciliation | 1 | 17 ms |

The slowest is 1.6 seconds and it is aggregating 3.66 million bridge rows. In a browser tab.

---

## 2. How it is put together

| piece | choice | why |
|---|---|---|
| engine | DuckDB compiled to WebAssembly | a real analytical SQL engine, columnar, runs client side |
| data format | Parquet, zstd compressed, 19 files, 52.9 MiB | compresses 2.4 GB of PostgreSQL to 52.9 MiB and reads columns selectively |
| fact layout | one file per year | mirrors the PostgreSQL partitioning, so the layout is the same idea in both places |
| schema | `bootstrap.sql` recreates `marts` and `ref` as views | the published queries run unedited |
| hosting | GitHub Pages, static files | free, no server, same origin as the data |
| engine delivery | vendored into the repo, not a CDN | no third-party dependency at run time |

The build is four commands, and the second one is the interesting one:

```bash
python3 export_parquet.py    # PostgreSQL -> Parquet, types preserved
python3 parity_test.py       # both engines must agree, or the build fails
npm run build                # bundle the engine, write site/
# publish site/
```

---

## 3. The bug that justifies the parity test

The whole claim of this phase is that the SQL in phase 08 is the SQL that runs in the browser. That claim is easy to make and easy to break, because the two engines disagree in places where **neither of them raises an error**.

Phase 06 has a query that counts multi-race applicants after rolling HMDA's hierarchical race codes up to their top-level parent. It was written like this:

```sql
WHERE race_code ~ '^[1-5]'
```

| engine | result |
|---|---|
| PostgreSQL | 18,051 |
| DuckDB | **14,527** |

No error. No warning. A 20 percent difference in a published figure.

The cause: **PostgreSQL's `~` is a partial regex match and DuckDB's is a full match.** In PostgreSQL, `'22' ~ '^[1-5]'` is true, because the pattern matches somewhere in the string. In DuckDB the same expression is false, because `^[1-5]` has to match the entire string and `'22'` is two characters long.

```
duckdb:    SELECT '22' ~ '^[1-5]';                  -- false
duckdb:    SELECT regexp_matches('22', '^[1-5]');   -- true
postgres:  SELECT '22' ~ '^[1-5]';                  -- true
```

`regexp_matches` is not the fix, because in PostgreSQL it returns a set of text arrays rather than a boolean, so it cannot be dropped into a `WHERE` clause. The portable form is the one that needed no regex in the first place:

```sql
WHERE left(race_code, 1) IN ('1','2','3','4','5')
```

Which means the same thing in both engines, returns 18,051 in both, and is clearer than what it replaced.

A second difference, which at least fails loudly:

```sql
round(percentile_cont(0.5) WITHIN GROUP (ORDER BY spread), 1)
-- postgres: ERROR: function round(double precision, integer) does not exist
-- duckdb:   works
```

`percentile_cont` returns a double, and PostgreSQL only has `round(numeric, int)`. The portable form is `round(CAST(... AS numeric), 1)`, which both accept.

**So the repository runs a parity test rather than trusting the claim.** `parity_test.py` executes every file in `queries/` against both engines, normalises the output, and exits non-zero on any difference:

```
views:
  ok     marts.v_application  (1754846 rows, 41 columns)
  ok     marts.v_denial_reason  (438591 rows, 4 columns)
  ok     marts.v_application_race  (3662829 rows, 5 columns)

queries:
  ok     01_market_by_year.sql  (4 rows)
  ok     02_loan_type.sql  (4 rows)
  ...
  ok     22_reconciliation.sql  (1 rows)

all 36 queries and 3 views return identical results in both engines
```

That output is what makes the playground trustworthy. Without it, "the same queries run here" is a hope.

### 3.1 Three more differences the test caught later

Adding the twelve general-analysis queries in phase 08 took the suite from ten queries to twenty-two, and the first run failed on five checks. None of them raised an error in either engine. Phase 08b later added ten more, taking it to thirty-two, and the first run of those failed on one: a median interest rate that interpolated between two loans and landed either side of the third decimal in the two engines. That query now uses `percentile_disc`, which returns an observed value by position rather than an interpolated one, and is exact in both. A later pass added four descriptive KPI queries to phase 08 and moved the sex-by-race crosstab into phase 08b, taking the suite to thirty-six. Those passed first time, including the `LATERAL (VALUES ...)` unpivot in the portfolio summary, which the two engines agree on. The suite was then rebuilt from scratch for the current analysis and stands at forty-two queries, identified by section letter rather than by phase number: A1 to A7, B1 and B2, C1a to C7, D1 to D6, E1a to E11, F1 to F4.

**`ORDER BY ... DESC` sorts NULLs in opposite directions.** PostgreSQL puts NULLs first, DuckDB puts them last. The top-ten geography query ranks MSAs by dollars disbursed, and three MSAs with one or two applications and no disbursement floated to the top of the PostgreSQL list and the bottom of the DuckDB one. Two different top tens, no warning. Every ordering that can see a NULL now says `NULLS LAST` explicitly rather than relying on a default.

**Float division disagrees in the second decimal place.** Four queries divided a sum by `1e9` to report billions, and cast to `numeric` afterwards. `1e9` is a double, so the division happened in floating point and the two engines accumulated it differently: 290.13 against 290.14, 103.03 against 103.04. One percentage landed exactly on a rounding boundary, 12.2500018, and came out 12.2 in PostgreSQL and 12.3 in DuckDB. The fix is to cast *before* dividing and divide by an integer, so the arithmetic is exact decimal in both engines:

```sql
-- disagrees in the last cent
round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1')/1e9 AS numeric), 2)

-- agrees
round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
      / 1000000000, 2)
```

**A trailing NULL made a view look one column narrower than it is.** The view check compared column counts by reading one row. `psql` prints a NULL as an empty field, and Python's `str.strip()` treats the `\x1f` field separator as whitespace, so a row ending in NULL lost its final field and `v_denial_reason` reported three columns against DuckDB's four. The test now reads `information_schema.columns` instead of counting fields in a sample row. That one was a bug in the test, not in the data, which is its own kind of lesson: a test that can fail for reasons unrelated to what it is testing will eventually be ignored.

---

## 3.2 The views had drifted, and nothing was checking them

Worse than any of the above, and found only because the new denial-reason query was the first published query ever to read from a view.

`bootstrap.sql` recreates the `marts` and `ref` namespaces over the Parquet files so that the published queries run in the browser unchanged. The three labelled views in it were written by hand, and they had drifted from `migrations/007_views.sql`:

| view | what the browser had | what the database has |
|---|---|---|
| `v_denial_reason` | joined `code_field = 'denial_reason'`, which does not exist, so it returned **no rows at all** | joins `denial_reason_1` |
| `v_application` | 22 columns | **41 columns**, including `loan_type`, `lien_status`, `applicant_age` and `is_purchased_loan` |
| `v_application_race` | joined `code_field = 'race'` | joins `applicant_race_1` |

The playground footer claimed the views matched PostgreSQL exactly. They did not, and had not for some time. No test failed because no published query touched them, which is the whole failure: **coverage was being inferred from the absence of red rather than from the presence of a check.**

Two changes, and the second matters more than the first.

`playground/sync_views.py` now writes those definitions into `bootstrap.sql` from `pg_get_viewdef` against the live database, between markers, with two mechanical substitutions: `::text` casts removed, and `= ANY (ARRAY[...])` rewritten as `IN (...)`. It is the same principle as `catalog/build_catalog.py` generating the data dictionary from `pg_catalog`. A definition that is generated cannot drift from its source.

And `parity_test.py` now compares every view's row count and column count across both engines directly, whether or not a query happens to read from it. Generating the views stops this particular drift; checking them independently is what stops the next one.

---

## 4. Type fidelity, which is the other way this breaks

The export has to preserve types, not re-infer them. Read the CSVs back without saying what the columns are and DuckDB reasonably concludes that `action_taken` is a `BIGINT`, because every value in it looks like a number:

```
action_taken -> BIGINT       -- inferred
action_taken -> VARCHAR      -- what PostgreSQL actually has
```

At which point `action_taken IN ('1','3')` errors, `ref_code.code_value = f.action_taken` errors because one side is text and the other is not, and every query in phase 08 has to be rewritten for the browser. The portability claim dies quietly.

So `export_parquet.py` reads the real types out of the catalogue and imposes them:

```python
rows = psql(f"""SELECT column_name, data_type FROM information_schema.columns
                WHERE table_schema = '{schema}' AND table_name = '{table}'
                ORDER BY ordinal_position""")
```

then asserts that the thing it exists to protect actually holds:

```
type fidelity check: action_taken IN ('1','3') matched 283,192 rows
```

283,192 is the same number PostgreSQL gives for 2024 decided applications, so the round trip preserved both the type and the data.

The compression is worth stating too. 2.4 GB of PostgreSQL becomes **52.9 MiB of Parquet**, a 45 times reduction, because Parquet stores columns rather than rows and a column of repeated HMDA codes compresses to almost nothing. The `raw` schema and the indexes are not exported, which accounts for most of it; one held-back column accounts for 29.1 MiB more, which is section 5a. The fact table goes from 676 MB across four partitions to 41.7 MiB.

---

## 5. The range-request idea that measured worse, then turned out to be broken

DuckDB-WASM can read a Parquet file over HTTP with range requests, fetching only the row groups a query needs. This is the feature everyone cites when recommending this architecture, and it is why the fact table is split into one file per year.

It is controlled by one boolean, the `directIO` argument:

```js
await db.registerFileURL(name, url, duckdb.DuckDBDataProtocol.HTTP, /* directIO */ true);
```

Measured on a local server with range support, one year-filtered count:

| `directIO` | behaviour | data fetched for one query |
|---|---|---|
| `true` | HTTP range requests, read only what is needed | **142 MB** |
| `false` | buffer each file once on first touch | 0 MB |

The range-request version fetched 142 MB to answer a query against the then 82.0 MiB of data, because DuckDB-WASM does not cache what it reads through range requests. Each row group it needs is re-fetched, and a query that visits the same data twice pays twice. The buffered version had already downloaded the files at startup and answered from memory.

### Then `directIO: false` turned out not to be enough

`directIO: false` stops DuckDB reading row groups on demand. It does not stop DuckDB reading the files. `registerFileURL` hands DuckDB a URL either way, and DuckDB's own HTTP reader sizes the file with a `HEAD` request and then pulls it with `Range` requests. On GitHub Pages that is not safe, and the symptom was a set of queries that failed in the deployed playground while passing on the same engine version locally:

```
Invalid Error: TProtocolException: Invalid data
```

GitHub Pages serves `.parquet` with `Content-Encoding: gzip`. So the `Content-Length` in the `HEAD` response is the **compressed** size, and a `Range` request addresses offsets in the **compressed** stream:

| | 2022 fact table |
|---|---|
| `Content-Length` reported by `HEAD` | 23,220,636 bytes |
| actual file, after the browser ungzips it | 23,404,621 bytes |
| difference | 183,985 bytes |

DuckDB computes the Parquet footer's position as `length - 8 - footer_length`, from a length that is 184 KB short. The footer is 22,280 bytes, so the footer is not in the window at all, and every offset taken from it is wrong. What DuckDB then decodes is arbitrary bytes where it expects a Thrift structure, which is exactly what `TProtocolException: Invalid data` means. Whether a given query survived depended only on whether DuckDB's fallback happened to have the right bytes cached, which is why the failure looked like it belonged to particular queries rather than to the transport.

Proof, run in the browser against the deployed files:

```js
const r = await fetch(url);                     // plain GET, no Range
r.headers.get('content-length')                 // "23220636"  (gzipped)
(await r.arrayBuffer()).byteLength              // 23404621    (actual)
```

The files were never the problem. `PAR1` is present at both ends, the footer parses, the schema is complete. Only the access method was wrong.

The fix is to take the transport away from DuckDB. Fetch each file with `fetch`, which lets the browser undo the `Content-Encoding` it asked for, and register the bytes:

```js
const res = await fetch(new URL(name, location.href).href);
const buf = new Uint8Array(await res.arrayBuffer());
if (String.fromCharCode(buf[0], buf[1], buf[2], buf[3]) !== 'PAR1')
    throw new Error(`${name}: not a Parquet file`);
await db.registerFileBuffer(name, buf);
```

This costs the same download at startup that `directIO: false` already cost, answers every query from memory as before, and cannot be broken by what a host decides to do with `Content-Encoding`. The magic-bytes check turns a truncated or re-encoded download into a clear message at load time rather than a Thrift error inside the first query that touches the file.

The general lesson is the one worth keeping: a benchmark told us range requests were slower, and we acted on it, but we kept the mechanism that made them possible. The bug was in the part the benchmark did not cover.

The honest full accounting:

| | size | when |
|---|---|---|
| page | 25 kB | at load |
| DuckDB engine, WebAssembly | 17.7 MB | at load |
| Parquet data | 52.9 MiB | at load |
| all ten queries afterwards | 23 MB total, 0 to 8.5 MB each | as run |

About 94 MB for a visitor who loads the page and runs everything, of which the engine is now the largest single item. On a 50 Mbit connection that is roughly 15 seconds of downloading, once, and then a local analytical database that answers in milliseconds. On the local test server the page was ready in 1.0 second.

**A stated trade-off not taken.** The fact table is 41.7 of the 52.9 MiB and carries 40 columns. Exporting only the 17 columns the published queries use would shrink it further still. It is not done, because a playground where a reviewer can only run the queries I wrote is worth much less than one where they can explore the model I claim to have built. The number is here so the choice is visible rather than assumed. Section 5a is the one column that did come out, and the reason it is a different decision.

---

## 5a. The one column held back, and why it is not the same decision

The fact table was 70.8 MiB of the 82.0 MiB export. Measuring the Parquet metadata column by column, rather than assuming, gave this:

| column | compressed, four files | share of the fact export | read by any published query |
|---|---|---|---|
| `row_hash` | **30.5 MB** | **42.0 percent** | no |
| `loan_to_value_ratio` | 3.7 MB | 5.1 percent | yes |
| `total_loan_costs` | 3.3 MB | 4.5 percent | through `v_application` |
| `census_tract` | 3.2 MB | 4.4 percent | yes |
| every other column | under 2.8 MB each | | mixed |

`row_hash` is `md5(row::text)`, the deterministic key from phase 04. It earns its place in PostgreSQL: it is what makes the surrogate key reproducible across rebuilds, it is one half of the uniqueness assertion in phase 07, and phase 09 indexes it. In the browser it is 128 bits of hex per row that no query can read and no reviewer can interpret.

So it is held back from the export, in `EXCLUDE` in `export_parquet.py`, and the script asserts afterwards that no exported file still carries it.

| | before | after |
|---|---|---|
| fact table, four files | 70.8 MiB | **41.7 MiB** |
| whole export, nineteen files | 82.0 MiB | **52.9 MiB** |

A 35 percent smaller download, with every analytical column still present and every published figure unchanged: all forty-two queries were re-run against the trimmed export and A1 still returns 1,596,676 applications, 951,371 originated loans and 371,417,740,000 dollars.

**Why this is not the trade-off above.** That one was about withholding columns a reviewer might want to explore, and it was declined for that reason. This one is about a column there is nothing to explore in. The distinction that matters is not "does a query use it" but "could anyone use it", and those two questions give different answers for `total_points_and_fees`, which stays, and for `row_hash`, which goes.

`dup_seq` and `county_was_repaired` are load artifacts too and they stay, because they cost 0.01 MB between them and each supports a claim made elsewhere in these documents: `dup_seq` shows the duplicate handling, `county_was_repaired` shows the 181 repaired tract-years.

---

## 5b. What the parity test caught when it was finally run against all forty-two

The suite was rebuilt for the current analysis and the parity test had not been
run against it. On its first run, seven of forty-two disagreed. Two root causes,
neither of which raises an error in either engine.

### `NUMERIC` is not the same type in the two engines

In DuckDB, `NUMERIC` is an alias for `DECIMAL(18,3)`. Three decimal places. In
PostgreSQL it is arbitrary precision. So this, which appears in fourteen of the
published queries:

```sql
round(CAST(percentile_disc(0.5) WITHIN GROUP (ORDER BY ...) AS numeric), 2)
```

rounds **twice** in DuckDB and once in PostgreSQL. The median lender denial rate
on refinancing is 17.154582763337893 exactly:

| | DuckDB | PostgreSQL |
|---|---|---|
| `CAST(... AS numeric)` | 17.155 | 17.154582763337893 |
| then `round(..., 2)` | **17.16** | **17.15** |

Four published figures were wrong in the browser: a median loan-to-income of
2.26 against 2.25, 0.97 against 0.96, 2.31 against 2.30, and that 17.16 against
17.15. Each one had a 5 in the third decimal, which is the only place the double
rounding can bite, which is why it had never shown up in spot checks.

`round(CAST(x AS numeric), 3)` was safe only by coincidence, three being
DuckDB's default scale, and `round(CAST(x AS numeric))` to no decimals is at
risk the same way whenever the value sits on a boundary after a 3-decimal round.

All sixty-one casts in the published queries now name the precision:
`CAST(x AS DECIMAL(24,8))`, which means the same thing in both engines. Rounding
on an exact decimal is half-away-from-zero in both, verified on the boundary
cases: `round(CAST(2.255 AS DECIMAL(24,8)), 2)` is 2.26 and
`round(CAST(2.245 AS DECIMAL(24,8)), 2)` is 2.25, matching PostgreSQL.

This is the same class of error as `percentile_cont` interpolating, and it is
worth stating the general rule it teaches: **an unqualified type name is not a
portable type.** `numeric` reads like "exact decimal, as much as you need" and in
one of the two engines it means "three decimal places".

### The test itself was dropping columns

Three more failures were the test, not the queries. All three were on the last
row of a 1,139-row result, the one lender with no interest rate and no loan
amounts, and in each case PostgreSQL appeared to return fewer columns than
DuckDB, with the missing ones being trailing NULLs.

The field separator is `\x1f`, the ASCII unit separator, chosen because it
cannot occur in any value in this dataset. It is also whitespace as far as
Python is concerned: Unicode classes U+001C to U+001F as whitespace, so
`'\x1f'.isspace()` is `True`. `out.stdout.strip()` therefore removed the
trailing separators of the final line, and a row ending in NULLs came back
short:

```python
>>> line = 'Bank of Hawaii\x1f2\x1f0\x1f0\x1f0\x1f\x1f\x1f\x1f\x1f'
>>> len(line.split('\x1f'))
10
>>> len(line.strip().split('\x1f'))
5
```

Only the last line of output could be affected, which is exactly where all three
failures were. The test now splits the raw output rather than a stripped copy,
prints NULL as an explicit sentinel so no field is ever zero-length, and fails a
query whose rows are not all the same width rather than comparing ragged lists.

### Result

Both causes fixed, forty-two of forty-two agree. Seven table cells in the
README moved by 0.01 and one sentence of prose with them.

---

## 6. Two more things that had to be measured rather than assumed

**The engine version matters.** DuckDB-WASM 1.29.0 made the Parquet reader a dynamically loaded extension, so the page tries to fetch `extensions.duckdb.org/v1.1.1/wasm_eh/parquet.duckdb_extension.wasm` at startup and dies with `table index is out of bounds` if that host is unreachable. 1.28.0 links Parquet statically. The version is pinned in `package.json` with that reason written next to it, because "upgrade to the latest" would silently reintroduce a network dependency and an unhelpful error message.

The older build is also half the size: 18 MB of WebAssembly against 35 MB.

**Relative paths do not work for the worker.** The engine's worker script resolves `mainModule` against its own location, not the page's, so `./vendor/duckdb-eh.wasm` becomes `/vendor/vendor/duckdb-eh.wasm` and 404s. The bundle config uses absolute URLs built from `location.href`. This took a headless browser and a 404 log to find, and no amount of reading the page source would have shown it.

---

## 7. What was rejected

| option | why not |
|---|---|
| A hosted PostgreSQL with a public read-only user | costs money, needs maintenance, and dies the day the free tier changes |
| A screenshot of results in the README | proves nothing, and is exactly the problem this phase exists to solve |
| A Jupyter notebook on Binder | cold starts of minutes, frequent queue failures, and it is Python rather than SQL |
| Loading the CSVs directly in the browser | 638 MB against 52.9 MiB, and no column pruning |
| PGlite, PostgreSQL compiled to WASM | genuinely the same dialect, but single threaded with no columnar execution, so the 3.66 million row bridge aggregates are not viable |
| DuckDB-WASM from a CDN | smaller repository, but a run-time dependency on a third party for something meant to still work in five years |
| Hive-partitioned paths with a glob | DuckDB-WASM cannot glob over HTTP, so the files have to be listed, which is what `bootstrap.sql` does |

The PGlite line is the one worth expanding, because it was the closer call. PGlite would have removed this entire phase's dialect problem: same engine, same `~` operator, no parity test needed. It loses on execution model. DuckDB is a columnar vectorised engine and PGlite is single-threaded row-at-a-time PostgreSQL in WASM, and the queries here aggregate millions of rows. The dialect gap was the cheaper problem to solve, and solving it produced the parity test, which is a better artefact than the problem it fixed.

---

## 8. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| DuckDB-WASM | PGlite, same dialect | columnar execution is what makes 3.66 million row aggregates viable in a tab |
| A parity test in the repository | trusting that the SQL is portable | one silent regex difference changed a published figure by 20 percent |
| Types read from `information_schema` | let the CSV reader infer | inferred `BIGINT` codes break every published query |
| `bootstrap.sql` recreating `marts` and `ref` | rewrite the queries for Parquet paths | one version of every query, not two |
| `fetch` plus `registerFileBuffer` | `registerFileURL`, any `directIO` | 142 MB per query against 0, and no HTTP range reads to be broken by a gzipping host |
| Engine vendored, version pinned | CDN, latest version | 1.29.0 needs a network fetch to read Parquet at all |
| Ship all 40 fact columns | 17 columns and half the download | a playground you can only run my queries in is worth much less |
| Static files on GitHub Pages | a hosted database | nothing to pay for and nothing to keep alive |
| Generating bootstrap.sql views from pg_get_viewdef | writing them by hand | the hand-written ones drifted, silently, for months |
| Checking views in the parity test directly | relying on queries to touch them | no published query touched them, so nothing failed |
| `NULLS LAST` written out in full | the engine default | the two engines have opposite defaults and neither warns |
| Exact decimal arithmetic rather than float | `/1e9` | the two engines disagreed in the second decimal place |
