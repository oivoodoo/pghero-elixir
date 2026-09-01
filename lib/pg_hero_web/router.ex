defmodule PgHeroWeb.Router do
  @moduledoc """
  Router helper for mounting PgHero in a Phoenix application.

      import PgHeroWeb.Router

      scope "/" do
        pipe_through [:browser, :require_admin]
        pghero "/pghero"
      end
  """

  defmacro pghero(path, opts \\ []) do
    routes = page_routes()

    quote bind_quoted: [path: path, opts: opts], unquote: true do
      # Include parent Phoenix scopes so asset/nav URLs match the real mount
      # (e.g. scope "/dev" + pghero("/pghero") => "/dev/pghero").
      mount_path = Phoenix.Router.scoped_path(__MODULE__, path)

      pipeline_name =
        mount_path
        |> String.trim("/")
        |> String.replace(~r/[^A-Za-z0-9_]/, "_")
        |> then(&:"pghero_#{&1}")

      pipeline pipeline_name do
        plug :put_root_layout, false
        plug :put_layout, html: {PgHeroWeb.Layouts, :app}
        plug PgHeroWeb.Plugs.Dashboard, Keyword.put(opts, :mount_path, mount_path)
      end

      scope path, alias: false, as: false do
        pipe_through pipeline_name

        get "/assets/:file", PgHeroWeb.AssetController, :show
        unquote(routes)

        scope "/:database", alias: false, as: false do
          unquote(routes)
        end
      end
    end
  end

  defp page_routes do
    quote do
      get "/", PgHeroWeb.HomeController, :index
      get "/space", PgHeroWeb.HomeController, :space
      get "/space/:relation", PgHeroWeb.HomeController, :relation_space
      get "/index_bloat", PgHeroWeb.HomeController, :index_bloat
      get "/live_queries", PgHeroWeb.HomeController, :live_queries
      get "/queries", PgHeroWeb.HomeController, :queries
      get "/queries/:query_hash", PgHeroWeb.HomeController, :show_query
      get "/explain", PgHeroWeb.HomeController, :explain
      get "/tune", PgHeroWeb.HomeController, :tune
      get "/connections", PgHeroWeb.HomeController, :connections
      get "/maintenance", PgHeroWeb.HomeController, :maintenance
      post "/kill", PgHeroWeb.HomeController, :kill
      post "/kill_long_running_queries", PgHeroWeb.HomeController, :kill_long_running_queries
      post "/kill_all", PgHeroWeb.HomeController, :kill_all
      post "/enable_query_stats", PgHeroWeb.HomeController, :enable_query_stats
      post "/explain", PgHeroWeb.HomeController, :explain
      post "/reset_query_stats", PgHeroWeb.HomeController, :reset_query_stats
    end
  end
end
