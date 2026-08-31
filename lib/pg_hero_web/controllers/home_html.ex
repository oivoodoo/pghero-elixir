defmodule PgHeroWeb.HomeHTML do
  @moduledoc false
  use PgHeroWeb, :html

  embed_templates "home_html/*"

  attr :conn, :any, required: true
  attr :queries, :list, required: true
  attr :vacuum_progress, :map, default: %{}
  attr :kill_enabled, :boolean, default: false
  attr :explain_enabled, :boolean, default: true

  def live_queries_table(assigns) do
    ~H"""
    <table class="table queries">
      <thead>
        <tr>
          <th class="width-25">Pid</th>
          <th class="width-25">Duration</th>
          <th class="width-25">State</th>
          <th class="width-25"></th>
        </tr>
      </thead>
      <tbody>
        <%= for query <- Enum.reverse(@queries) do %>
          <tr>
            <td>{query[:pid]}</td>
            <td>{format_duration_ms(query[:duration_ms])}</td>
            <td>
              {query[:state]}
              <%= if vp = @vacuum_progress[query[:pid]] do %>
                <br />
                <strong>{vp[:phase]}</strong>
              <% end %>
            </td>
            <td class="text-right">
              <%= if @explain_enabled do %>
                <form
                  action={pg_path(@conn, "explain")}
                  method="post"
                  target="_blank"
                  class="button_to"
                >
                  <input
                    :if={token = csrf_token(@conn)}
                    type="hidden"
                    name="_csrf_token"
                    value={token}
                  />
                  <input type="hidden" name="query" value={query[:query]} />
                  <button class="btn btn-info" type="submit">Explain</button>
                </form>
              <% end %>
              <%= if @kill_enabled do %>
                <form action={pg_path(@conn, "kill")} method="post" class="button_to">
                  <input
                    :if={token = csrf_token(@conn)}
                    type="hidden"
                    name="_csrf_token"
                    value={token}
                  />
                  <input type="hidden" name="pid" value={query[:pid]} />
                  <button class="btn btn-danger" type="submit">Kill</button>
                </form>
              <% end %>
            </td>
          </tr>
          <tr>
            <td colspan="4" class="query-row">
              {query[:source]} <span class="text-muted">{query[:user]}</span>
              <pre class="query-pre"><code class="language-pgsql"><%= query[:query] %></code></pre>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <script>
      highlightQueries();
    </script>
    """
  end

  attr :connection_sources, :list, required: true

  def connections_table(assigns) do
    ~H"""
    <table class="table">
      <thead>
        <tr>
          <th>Top Sources</th>
          <th class="width-20">Connections</th>
        </tr>
      </thead>
      <tbody>
        <%= for source <- @connection_sources do %>
          <tr>
            <td>
              {source[:source]}
              <div class="text-muted">
                {Enum.join(
                  Enum.reject([source[:user], source[:database], source[:ip]], &is_nil/1),
                  " - "
                )}
              </div>
            </td>
            <td>{number_with_delimiter(source[:total_connections])}</td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end
end
