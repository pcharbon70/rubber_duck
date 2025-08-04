defmodule RubberDuck.Jido.Actions.Generation.TemplateRenderAction do
  @moduledoc """
  Action for rendering code templates with dynamic content.

  This action handles template-based code generation, supporting various
  template engines and template versioning for consistent code generation
  across projects.

  ## Parameters

  - `template_name` - Name of the template to render (required)
  - `template_data` - Data to interpolate into the template (required)
  - `template_version` - Specific version of template (default: :latest)
  - `language` - Target programming language (default: :elixir)
  - `output_format` - Output format (default: :code)

  ## Returns

  - `{:ok, result}` - Template rendered successfully
  - `{:error, reason}` - Template rendering failed

  ## Example

      params = %{
        template_name: "genserver_basic",
        template_data: %{
          module_name: "UserSessionManager",
          state_fields: [:user_id, :session_id, :expires_at]
        },
        language: :elixir
      }

      {:ok, result} = TemplateRenderAction.run(params, context)
  """

  use Jido.Action,
    name: "template_render",
    description: "Render code templates with dynamic content",
    schema: [
      template_name: [
        type: :string,
        required: true,
        doc: "Name of the template to render"
      ],
      template_data: [
        type: :map,
        required: true,
        doc: "Data to interpolate into the template"
      ],
      template_version: [
        type: {:or, [:atom, :string]},
        default: :latest,
        doc: "Specific version of template"
      ],
      language: [
        type: :atom,
        default: :elixir,
        doc: "Target programming language"
      ],
      output_format: [
        type: :atom,
        default: :code,
        doc: "Output format (code, test, documentation)"
      ]
    ]

  require Logger

  @template_directory "priv/templates/generation"

  @impl true
  def run(params, _context) do
    Logger.info("Rendering template: #{params.template_name}")

    with {:ok, template_content} <- load_template(params),
         {:ok, rendered_code} <- render_template(template_content, params),
         {:ok, validated_code} <- validate_rendered_code(rendered_code, params) do
      
      result = %{
        rendered_code: validated_code,
        template_name: params.template_name,
        template_version: params.template_version,
        language: params.language,
        metadata: %{
          template_data: params.template_data,
          rendered_at: DateTime.utc_now(),
          template_source: get_template_source(params),
          output_format: params.output_format
        }
      }

      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Template rendering failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp load_template(params) do
    template_path = build_template_path(params)
    
    case File.read(template_path) do
      {:ok, content} ->
        {:ok, content}
      
      {:error, :enoent} ->
        # Try to find template in embedded templates
        case load_embedded_template(params) do
          {:ok, content} -> {:ok, content}
          {:error, _} -> {:error, {:template_not_found, params.template_name}}
        end
      
      {:error, reason} ->
        {:error, {:template_load_error, reason}}
    end
  end

  defp build_template_path(params) do
    version_suffix = if params.template_version == :latest do
      ""
    else
      "_#{params.template_version}"
    end
    
    Path.join([
      @template_directory,
      to_string(params.language),
      "#{params.template_name}#{version_suffix}.eex"
    ])
  end

  defp load_embedded_template(params) do
    # Load from embedded templates for common patterns
    case params.template_name do
      "genserver_basic" -> {:ok, genserver_basic_template()}
      "module_basic" -> {:ok, module_basic_template()}
      "function_basic" -> {:ok, function_basic_template()}
      _ -> {:error, :template_not_found}
    end
  end

  defp render_template(template_content, params) do
    try do
      # Use EEx for template rendering
      rendered = EEx.eval_string(template_content, assigns: params.template_data)
      {:ok, rendered}
    rescue
      error ->
        Logger.error("Template rendering error: #{inspect(error)}")
        {:error, {:render_error, error}}
    end
  end

  defp validate_rendered_code(code, params) do
    case params.language do
      :elixir ->
        case Code.string_to_quoted(code) do
          {:ok, _ast} -> {:ok, code}
          {:error, {_meta, message, _token}} -> 
            {:error, {:syntax_error, message}}
        end
      
      _ ->
        # For other languages, basic validation or assume valid
        {:ok, code}
    end
  end

  defp get_template_source(params) do
    "#{params.template_name}/#{params.template_version}"
  end

  # Embedded templates for common patterns

  defp genserver_basic_template do
    """
    defmodule <%= Map.get(assigns, :module_name, "MyGenServer") %> do
      @moduledoc \"\"\"
      <%= Map.get(assigns, :description, "A GenServer for managing state") %>
      \"\"\"

      use GenServer

      require Logger

      # Client API

      def start_link(opts \\\\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

    <%= if Map.get(assigns, :state_fields) do %>
      @type state :: %{
    <%= for field <- Map.get(assigns, :state_fields, []) do %>
        <%= field %>: term(),
    <% end %>
      }
    <% end %>

      # Server callbacks

      @impl true
      def init(opts) do
        state = %{
    <%= if Map.get(assigns, :state_fields) do %>
    <%= for field <- Map.get(assigns, :state_fields, []) do %>
          <%= field %>: Keyword.get(opts, :<%= field %>),
    <% end %>
    <% end %>
        }
        
        Logger.info("#{__MODULE__} started")
        {:ok, state}
      end

      @impl true
      def handle_call(:get_state, _from, state) do
        {:reply, state, state}
      end

      @impl true
      def handle_cast({:update_state, updates}, state) do
        new_state = Map.merge(state, updates)
        {:noreply, new_state}
      end

      @impl true
      def handle_info(msg, state) do
        Logger.debug("\#{__MODULE__} received unexpected message: \#{inspect(msg)}")
        {:noreply, state}
      end
    end
    """
  end

  defp module_basic_template do
    """
    defmodule <%= Map.get(assigns, :module_name, "MyModule") %> do
      @moduledoc \"\"\"
      <%= Map.get(assigns, :description, "Module documentation") %>
      \"\"\"

    <%= if Map.get(assigns, :functions) do %>
    <%= for function <- Map.get(assigns, :functions, []) do %>
      def <%= Map.get(function, :name, "function") %>(<%= Map.get(function, :params, "") %>) do
        <%= Map.get(function, :body, "# TODO: Implement function") %>
      end

    <% end %>
    <% end %>
    end
    """
  end

  defp function_basic_template do
    """
    def <%= Map.get(assigns, :function_name, "function") %>(<%= Map.get(assigns, :params, "") %>) do
      <%= Map.get(assigns, :body, "# TODO: Implement function") %>
    end
    """
  end
end