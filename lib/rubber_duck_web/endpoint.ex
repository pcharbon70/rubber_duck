defmodule RubberDuckWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :rubber_duck

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_rubber_duck_key",
    signing_salt: "VqJKNgP5",
    same_site: "Lax"
  ]

  socket("/socket", RubberDuckWeb.UserSocket,
    websocket: [
      connect_info: [:uri, :peer_data],
      check_origin: false,
      # Change from :info to :debug to reduce verbosity
      log: :debug
    ],
    longpoll: false
  )

  # Separate socket for authentication that doesn't require credentials
  socket("/auth_socket", RubberDuckWeb.AuthSocket,
    websocket: [
      connect_info: [:uri, :peer_data],
      check_origin: false,
      log: :debug
    ],
    longpoll: false
  )

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :rubber_duck,
    gzip: false,
    only: RubberDuckWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug RubberDuckWeb.Router
end
