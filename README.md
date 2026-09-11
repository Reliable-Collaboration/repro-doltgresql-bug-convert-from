# DoltgreSQL 1.3.1: `convert_from()` is not found

On DoltgreSQL 1.3.1, `convert_from`, the function that turns bytes in a named encoding into text, does not
exist, while its inverse `convert_to` works. `SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8')` answers:

```
ERROR:  function: 'convert_from' not found
```

PostgreSQL 18.6 returns `hello`.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the two images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-convert-from.git
cd repro-doltgresql-bug-convert-from
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in throwaway containers, waits until each accepts
connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container, and prints
the two outputs side by side. It exits 0 when DoltgreSQL's output is identical to PostgreSQL's and 1 when it
differs, and removes both containers either way.

To try another DoltgreSQL release, name its image (`POSTGRES_IMAGE` does the same for PostgreSQL):

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-convert-from-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-convert-from-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-convert-from-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-convert-from-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-convert-from-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-convert-from-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-convert-from-postgres repro-doltgresql-bug-convert-from-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few seconds
and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- convert_to: text to bytes in the UTF8 encoding.
SELECT convert_to('hello', 'UTF8');

-- convert_from: the same bytes back to text.
SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8');
```

## Expected behavior

Both statements succeed: `convert_to` turns `hello` into the bytes `\x68656c6c6f`, and `convert_from` turns
those bytes back into `hello`. This is what PostgreSQL 18.6 does:

```
-- convert_to: text to bytes in the UTF8 encoding.
SELECT convert_to('hello', 'UTF8');
  convert_to  
--------------
 \x68656c6c6f
(1 row)

-- convert_from: the same bytes back to text.
SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8');
 convert_from 
--------------
 hello
(1 row)
```

## Actual behavior

`convert_to` returns the same bytes as on PostgreSQL, but `convert_from` is not found. This is what
DoltgreSQL 1.3.1 does:

```
-- convert_to: text to bytes in the UTF8 encoding.
SELECT convert_to('hello', 'UTF8');
  convert_to  
--------------
 \x68656c6c6f
(1 row)

-- convert_from: the same bytes back to text.
SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8');
psql:/tmp/repro.sql:5: ERROR:  function: 'convert_from' not found
```

## Side by side

The full output of `./repro.sh`. `diff` cuts lines that are wider than its column, so the error on the right
is shortened here; it is shown in full under Actual behavior.

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- convert_to: text to bytes in the UTF8 encoding.            -- convert_to: text to bytes in the UTF8 encoding.
SELECT convert_to('hello', 'UTF8');                           SELECT convert_to('hello', 'UTF8');
  convert_to                                                    convert_to  
--------------                                                --------------
 \x68656c6c6f                                                  \x68656c6c6f
(1 row)                                                       (1 row)

-- convert_from: the same bytes back to text.                 -- convert_from: the same bytes back to text.
SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8');           SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8');
 convert_from                                               | psql:/tmp/repro.sql:5: ERROR:  function: 'convert_from' not
--------------                                              <
 hello                                                      <
(1 row)                                                     <
                                                            <

Result: DoltgreSQL's output differs from PostgreSQL's on 1 line(s), marked with |.
```

## Other observations

Each was run with `psql` on DoltgreSQL 1.3.1 and on PostgreSQL 18.6, in containers from the same images:

- Every other call of `convert_from` tried answers the same `function: 'convert_from' not found`:
  `SELECT convert_from('\x68656c6c6f', 'UTF8');` with an untyped argument,
  `SELECT pg_catalog.convert_from('\x68656c6c6f'::bytea, 'UTF8');`, the encoding names `'LATIN1'` and
  `'utf-8'`, and `SELECT convert_from(convert_to('hello', 'UTF8'), 'UTF8');`. PostgreSQL returns `hello` for
  each.
- `SELECT convert_from('\xe9'::bytea, 'LATIN1');` answers the same error. PostgreSQL returns `é`.
- Over a `bytea` column, `SELECT id, convert_from(b, 'UTF8') FROM t;` and
  `CREATE VIEW v AS SELECT id, convert_from(b, 'UTF8') AS s FROM t;` answer the same error. PostgreSQL
  returns `hello` and creates the view.
- These match PostgreSQL: `convert_to(chr(233), 'LATIN1')` returns `\xe9` and `convert_to(chr(233), 'UTF8')`
  returns `\xc3a9`; `encode` with `'escape'`, `'hex'` and `'base64'` returns `hello`, `68656c6c6f` and
  `aGVsbG8=`; `SELECT length('\x68656c6c6f'::bytea);` returns `5`.
- `decode` is not found either: `SELECT decode('68656c6c6f', 'hex');`, `SELECT decode('aGVsbG8=', 'base64');`
  and `SELECT decode('hello', 'escape');` answer `function: 'decode' not found`. PostgreSQL returns
  `\x68656c6c6f` for each.
- `SELECT convert('\x68656c6c6f'::bytea, 'UTF8', 'LATIN1');` answers `function: 'convert' not found`, and
  `SELECT length('\x68656c6c6f'::bytea, 'UTF8');` answers `function length(bytea, unknown) does not exist`.
  PostgreSQL returns `\x68656c6c6f` and `5`.
- `SELECT proname FROM pg_proc WHERE proname IN ('convert_from', 'convert_to', 'convert', 'encode', 'decode') ORDER BY 1;`
  returns `(0 rows)`, including for the two functions that work. PostgreSQL returns all five. Possibly related:
  [dolthub/doltgresql#3190](https://github.com/dolthub/doltgresql/issues/3190).
- `convert_to` was added in [dolthub/doltgresql#3189](https://github.com/dolthub/doltgresql/pull/3189). The
  feature list in [dolthub/doltgresql#3099](https://github.com/dolthub/doltgresql/issues/3099) marks
  `convert_to` done and does not name `convert_from`.

## Environment

- DoltgreSQL 1.3.1: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Ubuntu 26.04.1 LTS under WSL 2 (Linux
  6.18.33.2-microsoft-standard-WSL2, x86_64).
