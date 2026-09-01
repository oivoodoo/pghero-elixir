# PgHero

A performance dashboard for Postgres, as a **Phoenix library** or a **Docker image**.

This is an Elixir port of [ankane/pghero](https://github.com/ankane/pghero) 4.x.

## Docker

```sh
docker build -t pghero .
docker run --rm -ti -e DATABASE_URL=postgres://user:password@hostname:5432/dbname -p 8080:8080 pghero
```

Then visit [http://localhost:8080](http://localhost:8080). See [guides/Docker.md](guides/Docker.md) for auth, host-machine databases, and stats capture.

Without Docker:

```sh
DATABASE_URL=postgres://user:pass@localhost/dbname mix pghero.server
```

## Installation (Phoenix)

Add to `mix.exs`:

```elixir
def deps do
  [
    {:pghero, "~> 0.1.1"}
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

## Dummy app

A host Phoenix app lives in `dummy/` so you can see the mount without wiring your own project:

```sh
cd dummy
docker compose up -d
mix setup
mix phx.server
```

Then open [http://localhost:4000/pghero](http://localhost:4000/pghero).

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

Restart Postgres, then enable the extension from the Overview page (or `CREATE EXTENSION pg_stat_statements`). See [guides/Query-Stats.md](guides/Query-Stats.md) for RDS notes and troubleshooting.

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
just all-tests
```

`just all-tests` starts Postgres (via `dummy/docker-compose.yml`), creates `pghero_test`, and runs unit plus integration tests.

## License

MIT. Original work by Andrew Kane; Elixir/Phoenix port of the same dashboard.
