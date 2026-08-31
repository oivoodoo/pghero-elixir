# Changelog

## 0.1.0

Elixir/Phoenix port of [PgHero](https://github.com/ankane/pghero) 4.0.1.

- Mount the dashboard in a Phoenix router with `pghero "/pghero"`
- Query Postgres through an Ecto repo or a database URL
- Overview, queries, space, connections, live queries, maintenance, explain, and tune
- Optional historical query/space stats via `PgHero.Migrations`
- Optional HTTP basic auth

Not ported yet: suggested indexes (`pg_query`), AWS/GCP system charts.
