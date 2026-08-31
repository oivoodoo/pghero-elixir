defmodule PgHero.Standalone.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :pghero

  @session_options [
    store: :cookie,
    key: "_pghero_key",
    signing_salt: "pghero_salt",
    same_site: "Lax"
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PgHero.Standalone.Router
end
