defmodule RubberDuckWeb.HealthCheckController do
  use RubberDuckWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      service: "rubber_duck",
      timestamp: DateTime.utc_now()
    })
  end
end
