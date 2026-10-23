#!/usr/bin/env python3
"""
Export the PostgreSQL model to Parquet for the browser playground.

The point of this script is type fidelity. A naive CSV round trip lets DuckDB
infer its own types, and it guesses BIGINT for every HMDA code column because
the codes look like numbers. That silently breaks the project's central claim,
which is that the SQL published in the project README runs unchanged in the
browser:
in PostgreSQL action_taken is text, so the predicate is action_taken IN ('1','3'),
and against an inferred BIGINT column that predicate errors.

So the column types are read out of information_schema and imposed on the read,
rather than inferred. Codes stay VARCHAR, measures become DOUBLE, flags BOOLEAN.

Usage:  python3 export_parquet.py            (writes ./parquet/*.parquet)
"""
import os
import subprocess
import sys

import duckdb

# Defaults match a normal local install. Override with the PG* environment
# variables if your server is elsewhere. On Windows, set PGPASSWORD too, or
# psql will stop and ask for a password on every one of the nineteen dumps.
PG = dict(host=os.environ.get("PGHOST", "localhost"),
          port=os.environ.get("PGPORT", "5432"),
          user=os.environ.get("PGUSER", "postgres"),
          db=os.environ.get("PGDATABASE", "hmda"))

# psql takes its client encoding from the console codepage, which on Windows is
# usually WIN1252. Four institution names in dim_institution contain U+FFFD, the
# Unicode replacement character, left over from an encoding problem in the
# publisher's transmittal sheet (phase 03 section 4). U+FFFD has no WIN1252
# equivalent, so the dump of that one table fails with
#   character with byte sequence 0xef 0xbf 0xbd ... has no equivalent in WIN1252
# Forcing UTF8 here rather than relying on the shell means it cannot be forgotten.
ENV = {**os.environ, "PGCLIENTENCODING": "UTF8"}


# Columns held back from the export, by table.
#
# row_hash is md5(row::text), the deterministic key described in phase 04. It
# exists to deduplicate
# at load time, which it does in PostgreSQL, and it is the single largest column
# in the warehouse: 30.5 MB of the 70.8 MiB fact export, 42 percent of it, for a
# value no query can read and no reviewer can interpret. dup_seq and
# county_was_repaired are also load artifacts but cost 0.01 MB between them and
# each supports a claim the documentation makes, so they stay.
#
# This is not the same decision as the one in phase 10 section 5, which was
# whether to export only the columns the published queries use. That was
# declined on purpose: a playground a reviewer can only run my queries in is
# worth much less than one they can explore. row_hash is not a column anyone can
# explore. Dropping it takes the download from 82.0 MiB to 52.9 MiB and leaves
# every analytical column in place.
EXCLUDE = {
    ("marts", "fct_application"): ["row_hash"],
}

# (schema, table, optional year filter for partitioned output)
TABLES = [
    ("ref", "ref_code", None),
    ("ref", "assertion_catalog", None),
    ("marts", "dim_date", None),
    ("marts", "dim_institution", None),
    ("marts", "dim_tract", None),
    ("marts", "dim_county", None),
    ("marts", "dim_msa", None),
    ("marts", "dim_loan_product", None),
    ("marts", "dim_dwelling", None),
    ("marts", "dim_applicant_profile", None),
    ("marts", "br_application_race", None),
    ("marts", "br_application_ethnicity", None),
    ("marts", "br_denial_reason", None),
    ("marts", "br_underwriting_system", None),
    ("marts", "quarantine_application", None),
    ("marts", "fct_application", [2022, 2023, 2024, 2025]),
]

# PostgreSQL type -> DuckDB type. Deliberately conservative: anything textual
# stays textual so the published queries keep working.
TYPE_MAP = {
    "text": "VARCHAR",
    "character varying": "VARCHAR",
    "character": "VARCHAR",
    "integer": "INTEGER",
    "bigint": "BIGINT",
    "smallint": "SMALLINT",
    "numeric": "DOUBLE",
    "double precision": "DOUBLE",
    "real": "DOUBLE",
    "boolean": "BOOLEAN",
    "date": "DATE",
    "timestamp with time zone": "TIMESTAMP",
    "timestamp without time zone": "TIMESTAMP",
}


def fail(message):
    """Stop with psql's own error text, not a Python traceback."""
    sys.exit("\n".join([
        "",
        "Could not talk to PostgreSQL.",
        f"  host {PG['host']}   port {PG['port']}   user {PG['user']}   database {PG['db']}",
        "",
        message.strip(),
        "",
        "Most common causes, in order:",
        "  1. PGPORT is set to something your server is not listening on.",
        "     A standard install is 5432. Check with:  psql -U postgres -l",
        "     Clear an unwanted override with:         Remove-Item Env:PGPORT",
        "  2. PGPASSWORD is not set, or is wrong, in THIS shell window.",
        "  3. The database is not called 'hmda', or has not been built yet.",
        "",
    ]))


def psql(sql, tuples_only=True):
    cmd = ["psql", "-h", PG["host"], "-p", PG["port"], "-U", PG["user"],
           "-d", PG["db"], "-X", "-A", "-F", "\t", "-q", "-c", sql]
    if tuples_only:
        cmd.insert(-2, "-t")
    out = subprocess.run(cmd, capture_output=True, text=True, env=ENV)
    if out.returncode != 0:
        fail(out.stderr or f"psql exited with status {out.returncode}")
    return [l.split("\t") for l in out.stdout.strip().splitlines() if l]


def column_types(schema, table):
    rows = psql(f"""SELECT column_name, data_type FROM information_schema.columns
                    WHERE table_schema = '{schema}' AND table_name = '{table}'
                    ORDER BY ordinal_position""")
    if not rows or rows == [[""]]:
        sys.exit(f"{schema}.{table} not found")
    held = EXCLUDE.get((schema, table), [])
    missing = [h for h in held if h not in [r[0] for r in rows]]
    if missing:
        sys.exit(f"EXCLUDE names {missing} which {schema}.{table} does not have")
    mapped = {}
    for name, pgtype in rows:
        if name in held:
            continue
        duck = TYPE_MAP.get(pgtype)
        if duck is None:
            sys.exit(f"unmapped PostgreSQL type {pgtype!r} on {schema}.{table}.{name}")
        mapped[name] = duck
    if not mapped:
        sys.exit(f"{schema}.{table} has no columns left to export")
    return mapped


def dump_csv(schema, table, path, columns, where=""):
    # An explicit column list rather than SELECT *, so a held-back column never
    # reaches the CSV. The list comes from column_types, which has already
    # dropped it, which keeps the two in step by construction.
    select = ", ".join(f'"{c}"' for c in columns)
    sql = f"\\copy (SELECT {select} FROM {schema}.{table} {where}) TO '{path}' WITH (FORMAT csv, HEADER true)"
    out = subprocess.run(["psql", "-h", PG["host"], "-p", PG["port"], "-U", PG["user"],
                          "-d", PG["db"], "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                         capture_output=True, text=True, env=ENV)
    if out.returncode != 0:
        fail(out.stderr or f"psql exited with status {out.returncode} dumping {schema}.{table}")


def main():
    # Fail fast and legibly. Without this the first failure is a Python
    # traceback from inside a loop, which hides psql's own explanation.
    rows = psql("SELECT count(*) FROM marts.fct_application")
    print(f"connected to {PG['db']} on {PG['host']}:{PG['port']}, "
          f"{int(rows[0][0]):,} rows in marts.fct_application\n")

    os.makedirs("parquet", exist_ok=True)
    os.makedirs("tmp", exist_ok=True)
    con = duckdb.connect()
    total = 0

    for schema, table, years in TABLES:
        types = column_types(schema, table)
        type_literal = "{" + ", ".join(f"'{k}': '{v}'" for k, v in types.items()) + "}"

        for year in (years or [None]):
            name = table if year is None else f"{table}_{year}"
            where = "" if year is None else f"WHERE activity_year = {year}"
            csv = f"tmp/{name}.csv"
            out = f"parquet/{name}.parquet"

            dump_csv(schema, table, os.path.abspath(csv), list(types), where)
            con.execute(f"""COPY (SELECT * FROM read_csv('{csv}', header=true,
                                                         types={type_literal}))
                            TO '{out}' (FORMAT parquet, COMPRESSION zstd)""")
            os.remove(csv)
            size = os.path.getsize(out)
            total += size
            print(f"{name:34s} {size//1024:>7,} kB")

    os.rmdir("tmp")
    print(f"{'total':34s} {total//1024//1024:>7,} MB")

    # The claim this script exists to protect, checked rather than assumed.
    probe = con.execute("""SELECT count(*) FROM 'parquet/fct_application_2024.parquet'
                           WHERE action_taken IN ('1','3')""").fetchone()[0]
    print(f"\ntype fidelity check: action_taken IN ('1','3') matched {probe:,} rows")

    # Held-back columns, checked rather than assumed.
    for (schema, table), held in EXCLUDE.items():
        for f in sorted(os.listdir("parquet")):
            if not f.startswith(table):
                continue
            cols = [r[0] for r in con.execute(
                f"DESCRIBE SELECT * FROM 'parquet/{f}'").fetchall()]
            leaked = [h for h in held if h in cols]
            if leaked:
                sys.exit(f"{f} still carries {leaked}")
    print(f"held back from the export: "
          + ", ".join(f"{s}.{t}.{c}" for (s, t), cs in EXCLUDE.items() for c in cs))


if __name__ == "__main__":
    main()
