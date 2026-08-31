import Config

config :dummy,
  ecto_repos: [Dummy.Repo],
  generators: [timestamp_type: :utc_datetime]

config :dummy, DummyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DummyWeb.ErrorHTML, json: DummyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dummy.PubSub,
  live_view: [signing_salt: "dummy_live_view"]

config :phoenix, :json_library, Jason

# This is the host-app wiring under test: one repo, then mount /pghero.
config :pghero, repo: Dummy.Repo

import_config "#{config_env()}.exs"
