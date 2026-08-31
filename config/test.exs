import Config

config :pghero, PgHero.TestEndpoint,
  secret_key_base: String.duplicate("abcdefghijklmnopqrstuvwxyz012345", 2),
  server: false,
  http: [port: 4002],
  live_view: [signing_salt: "pgherotest"]

config :logger, level: :warning
