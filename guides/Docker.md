# PgHero Docker

Run PgHero as a standalone dashboard, the same way as the original image.

## Run

Build the image:

```sh
docker build -t pghero .
```

Start the dashboard:

```sh
docker run --rm -ti -e DATABASE_URL=postgres://user:password@hostname:5432/dbname -p 8080:8080 pghero
```

Use URL-encoding for any special characters in the username or password.

For databases on the host machine, use `host.docker.internal` as the hostname (on Linux, this requires `--add-host=host.docker.internal:host-gateway`):

```sh
docker run --rm -ti \
  --add-host=host.docker.internal:host-gateway \
  -e DATABASE_URL=postgres://postgres:postgres@host.docker.internal:5432/dummy_dev \
  -p 8080:8080 \
  pghero
```

Then visit [http://localhost:8080](http://localhost:8080).

`PGHERO_DATABASE_URL` is accepted as well.

## Authentication

```sh
docker run --rm -ti \
  -e DATABASE_URL=... \
  -e PGHERO_USERNAME=link \
  -e PGHERO_PASSWORD=hyrule \
  -p 8080:8080 \
  pghero
```

Do not expose the dashboard on the public internet without auth.

## Without Docker

```sh
DATABASE_URL=postgres://user:pass@localhost/dbname mix pghero.server
```

Default port is `8080`. Override with `--port` or `PORT`.

## Historical stats

Create the stats tables, then capture them:

```sh
docker run --rm -ti -e DATABASE_URL=... -e PGHERO_SERVER=true pghero \
  bin/pghero eval "PgHero.capture_query_stats()"

docker run --rm -ti -e DATABASE_URL=... -e PGHERO_SERVER=true pghero \
  bin/pghero eval "PgHero.capture_space_stats()"
```

## Permissions

Use a dedicated Postgres role. See [guides/Permissions.md](guides/Permissions.md).
