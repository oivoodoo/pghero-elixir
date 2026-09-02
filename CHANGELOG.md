# Changelog

## 0.1.2

- Fix `ArgumentError` when explaining queries with `$1` bind placeholders (pg_stat_statements). EXPLAIN now uses Postgrex's simple query protocol so Postgres can apply `GENERIC_PLAN` instead of Postgrex trying to bind parameters.

## 0.1.1

- Build asset and navigation URLs from the full Phoenix scope path so a nested mount such as `scope "/dev"` + `pghero("/pghero")` serves `/dev/pghero/assets/...` instead of `/pghero/assets/...`.
- Include Permissions and Query Stats guides in Hex/ExDoc extras so README and Docker links resolve.
- Document `PgHero.Database` helpers without pointing ExDoc at hidden `PgHero.Methods.*` modules.

## 0.1.0

Elixir/Phoenix port of [PgHero](https://github.com/ankane/pghero) 4.0.1.

- Mount the dashboard in a Phoenix router with `pghero "/pghero"`
- Query Postgres through an Ecto repo or a database URL
- Overview, queries, space, connections, live queries, maintenance, explain, and tune
- Optional historical query/space stats via `PgHero.Migrations`
- Optional HTTP basic auth
- Standalone server and Docker image (`DATABASE_URL` + port 8080)

Not ported yet: suggested indexes (`pg_query`), AWS/GCP system charts.
