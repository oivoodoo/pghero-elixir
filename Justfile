set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

database_url := env_var_or_default("DATABASE_URL", "postgres://postgres:postgres@127.0.0.1:5432/pghero_test")

# List recipes
default:
    @just --list

# Unit tests only (skips integration unless DATABASE_URL is already set)
test:
    mix test

# Start Postgres, create pghero_test, and run unit + integration tests
all-tests: deps postgres
    DATABASE_URL={{database_url}} mix test

# Fetch Mix dependencies
deps:
    mix deps.get

# Start dummy Postgres and ensure the pghero_test database exists
postgres:
    docker compose -f dummy/docker-compose.yml up -d --wait
    docker compose -f dummy/docker-compose.yml exec -T postgres \
      psql -U postgres -c "CREATE DATABASE pghero_test" >/dev/null 2>&1 || true

# mix format
format:
    mix format
