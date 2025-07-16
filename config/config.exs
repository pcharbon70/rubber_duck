import Config

config :rubber_duck,
  ecto_repos: [RubberDuck.Repo],
  ash_domains: [
    RubberDuck.Instructions,
    RubberDuck.Memory,
    RubberDuck.Workspace,
    RubberDuck.Context,
    RubberDuck.Conversations
  ]

# Instructions system configuration
config :rubber_duck, :instructions,
  default_rules_directory: ".rules",
  discovery_priority: [".rules", "instructions", ".instructions"]

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

# Phoenix Configuration
config :rubber_duck, RubberDuckWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: RubberDuckWeb.ErrorHTML, json: RubberDuckWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RubberDuck.PubSub,
  live_view: [signing_salt: "2QrBwNKG"]

# Configure phoenix generators
config :phoenix, :json_library, Jason

# Configure Phoenix to filter sensitive parameters from logs
config :phoenix, :filter_parameters, ["password", "api_key", "token", "secret"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.0",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "telemetry.exs"
import_config "tower.exs"
import_config "llm.exs"
import_config "security.exs"
import_config "#{config_env()}.exs"
