defmodule PgHeroWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html],
        layouts: [html: PgHeroWeb.Layouts]

      import Plug.Conn
      import PgHeroWeb.Helpers
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0, view_module: 1, view_template: 1]
      import PgHeroWeb.Helpers
      unquote(verified_routes())
    end
  end

  defp verified_routes do
    quote do
      # Paths are built with PgHeroWeb.Helpers.pg_path/3 so the dashboard
      # works regardless of the mount prefix in the host router.
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
