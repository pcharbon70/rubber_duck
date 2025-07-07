defmodule RubberDuckWeb.Plugs.HealthCheck do
  @moduledoc """
  A Plug that provides health check endpoints for monitoring.

  This plug exposes:
  - `/health` - Basic health check
  - `/health/ready` - Readiness check (are all services ready?)
  - `/health/live` - Liveness check (is the app running?)

  ## Usage

  Add to your endpoint or router:

      plug RubberDuckWeb.Plugs.HealthCheck, path: "/health"
  """

  import Plug.Conn
  alias RubberDuck.{Repo, ErrorBoundary}

  @behaviour Plug

  @default_path "/health"

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, @default_path)

    %{
      path: path,
      ready_path: "#{path}/ready",
      live_path: "#{path}/live"
    }
  end

  @impl true
  def call(%Plug.Conn{request_path: path} = conn, %{path: path}) do
    handle_health_check(conn, :basic)
  end

  def call(%Plug.Conn{request_path: ready_path} = conn, %{ready_path: ready_path}) do
    handle_health_check(conn, :ready)
  end

  def call(%Plug.Conn{request_path: live_path} = conn, %{live_path: live_path}) do
    handle_health_check(conn, :live)
  end

  def call(conn, _opts), do: conn

  # Private functions

  defp handle_health_check(conn, type) do
    start_time = System.monotonic_time(:microsecond)

    {status, body} = perform_health_check(type)

    duration = System.monotonic_time(:microsecond) - start_time

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("x-health-check-duration-us", to_string(duration))
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp perform_health_check(:basic) do
    # Basic health check - just verify the app is running
    {200,
     %{
       status: "ok",
       service: "rubber_duck",
       timestamp: DateTime.utc_now()
     }}
  end

  defp perform_health_check(:ready) do
    # Readiness check - verify all services are ready
    checks = %{
      database: check_database(),
      error_boundary: check_error_boundary()
    }

    all_healthy = Enum.all?(checks, fn {_, %{healthy: healthy}} -> healthy end)
    status = if all_healthy, do: 200, else: 503

    body = %{
      status: if(all_healthy, do: "ready", else: "not_ready"),
      service: "rubber_duck",
      timestamp: DateTime.utc_now(),
      checks: checks
    }

    {status, body}
  end

  defp perform_health_check(:live) do
    # Liveness check - verify the app is alive and can respond
    # This is simpler than readiness - just checks basic functioning
    try do
      # Simple memory check
      memory = :erlang.memory(:total)

      {200,
       %{
         status: "alive",
         service: "rubber_duck",
         timestamp: DateTime.utc_now(),
         memory_bytes: memory,
         uptime_seconds: uptime_seconds()
       }}
    rescue
      error ->
        {500,
         %{
           status: "error",
           service: "rubber_duck",
           timestamp: DateTime.utc_now(),
           error: Exception.message(error)
         }}
    end
  end

  defp check_database do
    try do
      # Execute a simple query to verify database connectivity
      case Repo.query("SELECT 1") do
        {:ok, _result} ->
          %{
            healthy: true,
            message: "Database connection successful"
          }

        {:error, error} ->
          %{
            healthy: false,
            message: "Database query failed",
            error: inspect(error)
          }
      end
    rescue
      error ->
        %{
          healthy: false,
          message: "Database check failed",
          error: Exception.message(error)
        }
    end
  end

  defp check_error_boundary do
    try do
      stats = ErrorBoundary.stats()

      # Consider unhealthy if error rate is too high
      total_calls = stats.success_count + stats.error_count
      error_rate = if total_calls > 0, do: stats.error_count / total_calls, else: 0

      # Less than 50% error rate
      healthy = error_rate < 0.5

      %{
        healthy: healthy,
        message: "Error boundary operational",
        stats: %{
          success_count: stats.success_count,
          error_count: stats.error_count,
          error_rate: Float.round(error_rate, 3)
        }
      }
    rescue
      error ->
        %{
          healthy: false,
          message: "Error boundary check failed",
          error: Exception.message(error)
        }
    end
  end

  defp uptime_seconds do
    {uptime, _} = :erlang.statistics(:wall_clock)
    div(uptime, 1000)
  end
end
