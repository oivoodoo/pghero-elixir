defmodule PgHeroWeb.AssetController do
  use PgHeroWeb, :controller

  @assets %{
    "application.css" => "text/css",
    "application.js" => "text/javascript",
    "Chart.bundle.js" => "text/javascript",
    "chartkick.js" => "text/javascript",
    "highlight.min.js" => "text/javascript",
    "nouislider.js" => "text/javascript",
    "favicon.png" => "image/png"
  }

  def show(conn, %{"file" => file}) do
    case Map.get(@assets, file) do
      nil ->
        send_resp(conn, 404, "Not found")

      content_type ->
        path = Application.app_dir(:pghero, "priv/static/#{file}")

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_file(200, path)
    end
  end
end
