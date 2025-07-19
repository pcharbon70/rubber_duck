defmodule RubberDuck.Tool.ExternalRegistry do
  @moduledoc """
  Manages automatic registration of tools with external services.

  This GenServer:
  - Scans the tool registry on startup
  - Registers tools with configured external services
  - Handles tool updates and hot reloading
  - Manages versioning and compatibility
  """

  use GenServer

  alias RubberDuck.Tool
  alias RubberDuck.Tool.{Registry, ExternalAdapter}
  alias Phoenix.PubSub

  require Logger

  # Check for updates every 5 seconds in dev
  @registry_interval 5_000
  # @external_services [:openapi, :anthropic, :openai, :langchain]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers all tools with external services.
  """
  def register_all do
    GenServer.call(__MODULE__, :register_all)
  end

  @doc """
  Registers a specific tool with external services.
  """
  def register_tool(tool_module) do
    GenServer.call(__MODULE__, {:register_tool, tool_module})
  end

  @doc """
  Unregisters a tool from external services.
  """
  def unregister_tool(tool_name) do
    GenServer.call(__MODULE__, {:unregister_tool, tool_name})
  end

  @doc """
  Updates tool registration when tool definition changes.
  """
  def update_tool(tool_module) do
    GenServer.call(__MODULE__, {:update_tool, tool_module})
  end

  @doc """
  Gets the registration status of all tools.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Forces a re-scan of the tool registry.
  """
  def rescan do
    GenServer.cast(__MODULE__, :rescan)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Subscribe to tool registry updates
    PubSub.subscribe(RubberDuck.PubSub, "tool_registry:updates")

    state = %{
      registrations: %{},
      external_configs: load_external_configs(opts),
      auto_register: Keyword.get(opts, :auto_register, true),
      scan_interval: Keyword.get(opts, :scan_interval, @registry_interval)
    }

    # Initial registration on startup
    if state.auto_register do
      Process.send_after(self(), :initial_scan, 100)
    end

    # Schedule periodic rescans in development
    if Mix.env() == :dev and state.scan_interval > 0 do
      Process.send_after(self(), :periodic_scan, state.scan_interval)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:register_all, _from, state) do
    tools = Registry.list()
    results = Enum.map(tools, &register_tool_internal(&1, state))

    successful = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = Enum.count(results, fn {status, _} -> status == :error end)

    {:reply, {:ok, %{total: length(tools), successful: successful, failed: failed}}, state}
  end

  @impl true
  def handle_call({:register_tool, tool_module}, _from, state) do
    case register_tool_internal(tool_module, state) do
      {:ok, registration} ->
        new_registrations = Map.put(state.registrations, tool_module, registration)
        {:reply, :ok, %{state | registrations: new_registrations}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_tool, tool_name}, _from, state) do
    # Find tool module by name
    tool_module =
      Registry.list()
      |> Enum.find(fn mod ->
        Tool.metadata(mod).name == tool_name
      end)

    if tool_module do
      # Unregister from all external services
      Enum.each(state.external_configs, fn {service, config} ->
        unregister_from_service(tool_module, service, config)
      end)

      new_registrations = Map.delete(state.registrations, tool_module)
      {:reply, :ok, %{state | registrations: new_registrations}}
    else
      {:reply, {:error, :tool_not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_tool, tool_module}, _from, state) do
    # First unregister the old version
    if Map.has_key?(state.registrations, tool_module) do
      Enum.each(state.external_configs, fn {service, config} ->
        unregister_from_service(tool_module, service, config)
      end)
    end

    # Then register the new version
    case register_tool_internal(tool_module, state) do
      {:ok, registration} ->
        new_registrations = Map.put(state.registrations, tool_module, registration)
        {:reply, :ok, %{state | registrations: new_registrations}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status =
      state.registrations
      |> Enum.map(fn {tool_module, registration} ->
        metadata = Tool.metadata(tool_module)

        %{
          tool: metadata.name,
          version: metadata.version || "1.0.0",
          registered_at: registration.registered_at,
          services: registration.services
        }
      end)

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:rescan, state) do
    handle_info(:periodic_scan, state)
  end

  @impl true
  def handle_info(:initial_scan, state) do
    Logger.info("Performing initial tool registration scan...")

    tools = Registry.list()

    registrations =
      Enum.reduce(tools, %{}, fn tool_module, acc ->
        case register_tool_internal(tool_module, state) do
          {:ok, registration} ->
            Map.put(acc, tool_module, registration)

          {:error, reason} ->
            Logger.error("Failed to register tool #{inspect(tool_module)}: #{inspect(reason)}")
            acc
        end
      end)

    Logger.info("Registered #{map_size(registrations)} tools with external services")

    {:noreply, %{state | registrations: registrations}}
  end

  @impl true
  def handle_info(:periodic_scan, state) do
    # Check for new or updated tools
    current_tools = Registry.list()
    registered_tools = Map.keys(state.registrations)

    # Find new tools
    new_tools = current_tools -- registered_tools

    # Find removed tools
    removed_tools = registered_tools -- current_tools

    # Register new tools
    new_registrations =
      Enum.reduce(new_tools, state.registrations, fn tool_module, acc ->
        case register_tool_internal(tool_module, state) do
          {:ok, registration} ->
            Logger.info("Registered new tool: #{inspect(tool_module)}")
            Map.put(acc, tool_module, registration)

          {:error, _reason} ->
            acc
        end
      end)

    # Unregister removed tools
    final_registrations =
      Enum.reduce(removed_tools, new_registrations, fn tool_module, acc ->
        Enum.each(state.external_configs, fn {service, config} ->
          unregister_from_service(tool_module, service, config)
        end)

        Logger.info("Unregistered removed tool: #{inspect(tool_module)}")
        Map.delete(acc, tool_module)
      end)

    # Schedule next scan
    if state.scan_interval > 0 do
      Process.send_after(self(), :periodic_scan, state.scan_interval)
    end

    {:noreply, %{state | registrations: final_registrations}}
  end

  @impl true
  def handle_info({:tool_updated, tool_module}, state) do
    # Handle hot reload updates
    Logger.info("Tool updated: #{inspect(tool_module)}, re-registering...")

    # Update the registration
    case register_tool_internal(tool_module, state) do
      {:ok, registration} ->
        new_registrations = Map.put(state.registrations, tool_module, registration)
        {:noreply, %{state | registrations: new_registrations}}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tool_removed, tool_module}, state) do
    # Handle tool removal
    Logger.info("Tool removed: #{inspect(tool_module)}, unregistering...")

    # Unregister from all services
    Enum.each(state.external_configs, fn {service, config} ->
      unregister_from_service(tool_module, service, config)
    end)

    new_registrations = Map.delete(state.registrations, tool_module)
    {:noreply, %{state | registrations: new_registrations}}
  end

  # Private functions

  defp load_external_configs(opts) do
    # Load configuration for external services
    # In production, this would come from config files

    base_configs = %{
      openapi: %{
        enabled: true,
        endpoint: Keyword.get(opts, :openapi_endpoint, "/api/tools/openapi"),
        format: :openapi
      },
      anthropic: %{
        enabled: Keyword.get(opts, :anthropic_enabled, false),
        api_key: Keyword.get(opts, :anthropic_api_key),
        format: :anthropic
      },
      openai: %{
        enabled: Keyword.get(opts, :openai_enabled, false),
        api_key: Keyword.get(opts, :openai_api_key),
        format: :openai
      },
      langchain: %{
        enabled: Keyword.get(opts, :langchain_enabled, false),
        endpoint: Keyword.get(opts, :langchain_endpoint),
        format: :langchain
      }
    }

    # Filter only enabled services
    Enum.filter(base_configs, fn {_service, config} -> config.enabled end)
    |> Enum.into(%{})
  end

  defp register_tool_internal(tool_module, state) do
    metadata = Tool.metadata(tool_module)

    # Attempt registration with each configured service
    service_results =
      Enum.map(state.external_configs, fn {service, config} ->
        case register_with_service(tool_module, service, config) do
          :ok -> {service, :registered}
          {:error, reason} -> {service, {:failed, reason}}
        end
      end)

    # Check if at least one registration succeeded
    if Enum.any?(service_results, fn {_service, status} -> status == :registered end) do
      registration = %{
        tool_module: tool_module,
        tool_name: metadata.name,
        version: metadata.version || "1.0.0",
        registered_at: DateTime.utc_now(),
        services: Enum.into(service_results, %{})
      }

      {:ok, registration}
    else
      {:error, :all_registrations_failed}
    end
  end

  defp register_with_service(tool_module, service, config) do
    case service do
      :openapi ->
        # For OpenAPI, we just need to ensure the tool is available
        # The actual endpoint would be handled by a Phoenix controller
        :ok

      :anthropic ->
        register_with_anthropic(tool_module, config)

      :openai ->
        register_with_openai(tool_module, config)

      :langchain ->
        register_with_langchain(tool_module, config)

      _ ->
        {:error, :unsupported_service}
    end
  end

  defp register_with_anthropic(tool_module, _config) do
    # In a real implementation, this would use the Anthropic API
    # For now, we'll simulate success
    case ExternalAdapter.convert_metadata(tool_module, :anthropic) do
      {:ok, _spec} ->
        # Would send spec to Anthropic
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp register_with_openai(tool_module, _config) do
    # In a real implementation, this would use the OpenAI API
    # For now, we'll simulate success
    case ExternalAdapter.convert_metadata(tool_module, :openai) do
      {:ok, _spec} ->
        # Would send spec to OpenAI
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp register_with_langchain(tool_module, _config) do
    # In a real implementation, this would POST to LangChain endpoint
    # For now, we'll simulate success
    case ExternalAdapter.convert_metadata(tool_module, :langchain) do
      {:ok, _spec} ->
        # Would POST spec to LangChain
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unregister_from_service(tool_module, service, _config) do
    metadata = Tool.metadata(tool_module)

    case service do
      :openapi ->
        # OpenAPI doesn't need explicit unregistration
        :ok

      :anthropic ->
        # Would call Anthropic API to remove tool
        Logger.debug("Unregistering #{metadata.name} from Anthropic")
        :ok

      :openai ->
        # Would call OpenAI API to remove tool
        Logger.debug("Unregistering #{metadata.name} from OpenAI")
        :ok

      :langchain ->
        # Would DELETE from LangChain endpoint
        Logger.debug("Unregistering #{metadata.name} from LangChain")
        :ok

      _ ->
        :ok
    end
  end
end
