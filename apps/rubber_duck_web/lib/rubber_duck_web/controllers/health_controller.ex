defmodule RubberDuckWeb.HealthController do
  use RubberDuckWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      app: "rubber_duck_web",
      version: Application.spec(:rubber_duck_web, :vsn),
      timestamp: DateTime.utc_now()
    })
  end
end
