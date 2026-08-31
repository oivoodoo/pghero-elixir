# PgHero

A performance dashboard for Postgres, as a **Phoenix library**. Mount it on a route in any Elixir/Phoenix app.

This is an Elixir port of [ankane/pghero](https://github.com/ankane/pghero) 4.x.

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:pghero, path: "../pghero"}
    # or once published: {:pghero, "~> 0.1.0"}
  ]
end
```

Point it at your Ecto repo in `config/config.exs`:

```elixir
config :pghero, repo: MyApp.Repo
```

Mount it in `router.ex` behind your own authentication:

```elixir
import PgHeroWeb.Router

scope "/" do
  pipe_through [:browser, :require_admin]
  pghero "/pghero"
end
```

Then open `/pghero`.

## Authentication

PgHero does **not** authenticate by itself when you mount it in a Phoenix pipeline. Put it behind your admin plug, as in the example above.

Optional HTTP basic auth (in addition to, or instead of, your pipeline):

```elixir
config :pghero,
  repo: MyApp.Repo,
  username: "link",
  password: "hyrule"
```

Or pass credentials at mount time:

```elixir
pghero "/pghero", username: "link", password: "hyrule"
```

**Do not expose this dashboard on the public internet without auth.** It can show query text and kill backends.

## Multiple databases

```elixir
config :pghero,
  databases: [
    primary: [repo: MyApp.Repo],
    analytics: [url: System.get_env("ANALYTICS_DATABASE_URL"), name: "Analytics"]
  ]
```

Each entry accepts `:repo`, `:url`, and `:name`.

## What you get

Same dashboard as the Rails engine:

- Overview (connections, vacuums, sequences, invalid indexes, slow queries)
- Queries (`pg_stat_statements`)
- Space
- Connections
- Live queries (with kill)
- Maintenance
- Explain
- Tune

Requires **PostgreSQL 14+**.

## Query stats

Enable `pg_stat_statements` in `postgresql.conf`:

```
shared_preload_libraries = 'pg_stat_statements'
```

Restart Postgres, then enable the extension from the Overview page (or `CREATE EXTENSION pg_stat_statements`).

## Historical stats

Create the tables with an Ecto migration:

```elixir
defmodule MyApp.Repo.Migrations.CreatePgheroStats do
  use Ecto.Migration

  def up, do: PgHero.Migrations.up()
  def down, do: PgHero.Migrations.down()
end
```

Capture on a schedule (Oban, Quantum, or cron):

```elixir
PgHero.capture_query_stats()  # every 5 minutes
PgHero.capture_space_stats()  # daily
```

Or mix tasks:

```sh
mix pghero.capture_query_stats
mix pghero.capture_space_stats
```

## Configuration

```elixir
config :pghero,
  repo: MyApp.Repo,
  long_running_query_sec: 60,
  slow_query_ms: 20,
  slow_query_calls: 100,
  total_connections_threshold: 500,
  explain: true,          # true | false | "analyze"
  disable_kill: false,
  username: nil,
  password: nil
```

Environment variables from the original project still work (`PGHERO_USERNAME`, `PGHERO_PASSWORD`, `PGHERO_DATABASE_URL`, and the threshold vars).

## Permissions

Use a dedicated Postgres role. See [guides/Permissions.md](guides/Permissions.md).

## Not in this port yet

- Suggested indexes (`pg_query`)
- AWS RDS / GCP Cloud SQL system charts
- Query text filtering via `pg_query`

## Development

```sh
mix deps.get
mix test
DATABASE_URL=postgres://postgres:postgres@localhost/pghero_test mix test
```

## License

MIT. Original work by Andrew Kane; Elixir/Phoenix port of the same dashboard.
