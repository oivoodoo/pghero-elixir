defmodule DummyWeb.Router do
  use DummyWeb, :router
  import PgHeroWeb.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DummyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", DummyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # How a host Phoenix app mounts PgHero. In a real app, put this behind
  # an admin pipeline instead of (or in addition to) :browser.
  scope "/" do
    pipe_through :browser
    pghero "/pghero"
  end
end
