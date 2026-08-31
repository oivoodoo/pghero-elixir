defmodule PgHero.TestRouter do
  use Phoenix.Router
  import PgHeroWeb.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser
    pghero("/pghero")
  end
end

defmodule PgHero.TestEndpoint do
  use Phoenix.Endpoint, otp_app: :pghero

  @session_options [
    store: :cookie,
    key: "_pghero_test",
    signing_salt: "pgherotest"
  ]

  plug Plug.Session, @session_options
  plug PgHero.TestRouter
end
