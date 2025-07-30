defmodule RubberDuck.Tools.DocFetcher do
  @moduledoc """
  Retrieves documentation from online sources such as HexDocs or GitHub.
  
  This tool fetches and parses documentation for Elixir/Erlang modules,
  functions, and packages from various online sources.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :doc_fetcher
    description "Retrieves documentation from online sources such as HexDocs or GitHub"
    category :documentation
    version "1.0.0"
    tags [:documentation, :reference, :learning, :api]
    
    parameter :query do
      type :string
      required true
      description "Module, function, or package to fetch documentation for"
      constraints [
        min_length: 1,
        max_length: 200
      ]
    end
    
    parameter :source do
      type :string
      required false
      description "Documentation source to use"
      default "auto"
      constraints [
        enum: [
          "auto",      # Automatically determine best source
          "hexdocs",   # HexDocs.pm
          "erlang",    # Erlang.org docs
          "elixir",    # Elixir-lang.org docs
          "github",    # GitHub README/docs
          "local"      # Local project docs
        ]
      ]
    end
    
    parameter :doc_type do
      type :string
      required false
      description "Type of documentation to fetch"
      default "module"
      constraints [
        enum: [
          "module",     # Module documentation
          "function",   # Function documentation
          "type",       # Type specifications
          "callback",   # Behaviour callbacks
          "guide",      # Package guides
          "changelog"   # Version changelog
        ]
      ]
    end
    
    parameter :version do
      type :string
      required false
      description "Package version (for hex packages)"
      default "latest"
    end
    
    parameter :include_examples do
      type :boolean
      required false
      description "Include code examples from documentation"
      default true
    end
    
    parameter :include_related do
      type :boolean
      required false
      description "Include related functions/modules"
      default false
    end
    
    parameter :format do
      type :string
      required false
      description "Output format for documentation"
      default "markdown"
      constraints [
        enum: ["markdown", "plain", "html"]
      ]
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :restricted
      capabilities [:network]
      rate_limit 50
    end
  end
  
  @doc """
  Executes documentation fetching based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, parsed_query} <- parse_query(params),
         {:ok, source_url} <- determine_source_url(parsed_query, params),
         {:ok, raw_docs} <- fetch_documentation(source_url),
         {:ok, parsed_docs} <- parse_documentation(raw_docs, params),
         {:ok, formatted} <- format_documentation(parsed_docs, params) do
      
      {:ok, %{
        query: params.query,
        source: parsed_query.source,
        documentation: formatted,
        metadata: %{
          url: source_url,
          fetched_at: DateTime.utc_now(),
          version: parsed_query.version,
          type: params.doc_type
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp parse_query(params) do
    query = params.query
    
    parsed = cond do
      # Function notation: Module.function/arity
      query =~ ~r/^[A-Z][\w.]*\.\w+\/\d+$/ ->
        [module_func, arity] = String.split(query, "/")
        [module, function] = String.split(module_func, ".", parts: 2)
        %{
          type: :function,
          module: module,
          function: function,
          arity: String.to_integer(arity),
          package: extract_package_name(module)
        }
      
      # Module notation: Module or Module.SubModule
      query =~ ~r/^[A-Z][\w.]*$/ ->
        %{
          type: :module,
          module: query,
          package: extract_package_name(query)
        }
      
      # Package notation: package_name
      query =~ ~r/^[a-z][\w_]*$/ ->
        %{
          type: :package,
          package: query
        }
      
      # Type notation: t:Module.type_name/0
      query =~ ~r/^t:[A-Z][\w.]*\.\w+\/\d+$/ ->
        type_spec = String.slice(query, 2..-1)
        [module_type, arity] = String.split(type_spec, "/")
        [module, type_name] = String.split(module_type, ".", parts: 2)
        %{
          type: :type,
          module: module,
          type_name: type_name,
          arity: String.to_integer(arity),
          package: extract_package_name(module)
        }
      
      # Callback notation: c:Module.callback_name/arity
      query =~ ~r/^c:[A-Z][\w.]*\.\w+\/\d+$/ ->
        callback_spec = String.slice(query, 2..-1)
        [module_callback, arity] = String.split(callback_spec, "/")
        [module, callback] = String.split(module_callback, ".", parts: 2)
        %{
          type: :callback,
          module: module,
          callback: callback,
          arity: String.to_integer(arity),
          package: extract_package_name(module)
        }
      
      true ->
        %{type: :unknown, query: query}
    end
    
    # Determine source
    source = if params.source == "auto" do
      determine_best_source(parsed)
    else
      params.source
    end
    
    # Add version info
    parsed = Map.put(parsed, :version, params.version)
    parsed = Map.put(parsed, :source, source)
    
    {:ok, parsed}
  end
  
  defp extract_package_name(module_name) do
    # Common pattern: PackageName.Module.SubModule
    parts = String.split(module_name, ".")
    
    case hd(parts) do
      "Elixir" -> "elixir"
      "Erlang" -> "erlang"
      "Phoenix" -> "phoenix"
      "Ecto" -> "ecto"
      "Plug" -> "plug"
      "GenServer" -> "elixir"
      "Supervisor" -> "elixir"
      "Task" -> "elixir"
      "Agent" -> "elixir"
      "Stream" -> "elixir"
      "Enum" -> "elixir"
      "Map" -> "elixir"
      "List" -> "elixir"
      "String" -> "elixir"
      "Process" -> "elixir"
      "File" -> "elixir"
      "IO" -> "elixir"
      other -> 
        # Convert CamelCase to snake_case
        other
        |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
        |> String.downcase()
    end
  end
  
  defp determine_best_source(parsed) do
    cond do
      parsed.type == :package -> "hexdocs"
      Map.get(parsed, :package) == "elixir" -> "elixir"
      Map.get(parsed, :package) == "erlang" -> "erlang"
      Map.get(parsed, :module, "") =~ ~r/^:[a-z]/ -> "erlang"
      true -> "hexdocs"
    end
  end
  
  defp determine_source_url(parsed, params) do
    base_url = case parsed.source do
      "hexdocs" ->
        version = if parsed.version == "latest", do: "", else: parsed.version
        package = Map.get(parsed, :package, "unknown")
        "https://hexdocs.pm/#{package}/#{version}"
      
      "elixir" ->
        "https://hexdocs.pm/elixir/#{parsed.version}"
      
      "erlang" ->
        "https://www.erlang.org/doc/man"
      
      "github" ->
        # Would need to determine GitHub URL from package
        "https://github.com"
      
      "local" ->
        # Would read from local doc directory
        "file://doc"
      
      _ ->
        "https://hexdocs.pm"
    end
    
    url = case params.doc_type do
      "module" ->
        "#{base_url}/#{parsed.module}.html"
      
      "function" ->
        anchor = "#{parsed.function}/#{parsed.arity}"
        "#{base_url}/#{parsed.module}.html##{anchor}"
      
      "type" ->
        anchor = "t:#{parsed.type_name}/#{parsed.arity}"
        "#{base_url}/#{parsed.module}.html##{anchor}"
      
      "callback" ->
        anchor = "c:#{parsed.callback}/#{parsed.arity}"
        "#{base_url}/#{parsed.module}.html##{anchor}"
      
      "guide" ->
        "#{base_url}/readme.html"
      
      "changelog" ->
        "#{base_url}/changelog.html"
      
      _ ->
        base_url
    end
    
    {:ok, url}
  end
  
  defp fetch_documentation(url) do
    # In a real implementation, this would make HTTP requests
    # For now, we'll simulate with mock data
    
    mock_response = if url =~ ~r/hexdocs\.pm/ do
      generate_hexdocs_mock(url)
    else
      generate_generic_mock(url)
    end
    
    {:ok, mock_response}
  end
  
  defp generate_hexdocs_mock(url) do
    %{
      content: """
      <div class="summary">
        <h1>Module Documentation</h1>
        <p>This module provides functionality for the requested component.</p>
      </div>
      <div class="detail">
        <section class="docstring">
          <p>Detailed documentation content here...</p>
          <h2>Examples</h2>
          <pre><code class="elixir">
      iex> MyModule.my_function("test")
      {:ok, "result"}
          </code></pre>
        </section>
      </div>
      """,
      url: url,
      status: 200
    }
  end
  
  defp generate_generic_mock(url) do
    %{
      content: "Generic documentation content",
      url: url,
      status: 200
    }
  end
  
  defp parse_documentation(raw_docs, params) do
    if raw_docs.status != 200 do
      {:error, "Failed to fetch documentation: HTTP #{raw_docs.status}"}
    else
      parsed = %{
        raw_content: raw_docs.content,
        sections: extract_sections(raw_docs.content),
        examples: if(params.include_examples, do: extract_examples(raw_docs.content), else: []),
        related: if(params.include_related, do: extract_related_items(raw_docs.content), else: [])
      }
      
      {:ok, parsed}
    end
  end
  
  defp extract_sections(html_content) do
    # Simple extraction - in reality would use a proper HTML parser
    sections = []
    
    sections = if html_content =~ ~r/<h1[^>]*>([^<]+)<\/h1>/ do
      [{:title, extract_text_from_tag(html_content, "h1")} | sections]
    else
      sections
    end
    
    sections = if html_content =~ ~r/class="summary"/ do
      [{:summary, extract_summary(html_content)} | sections]
    else
      sections
    end
    
    sections = if html_content =~ ~r/class="docstring"/ do
      [{:description, extract_docstring(html_content)} | sections]
    else
      sections
    end
    
    sections = if html_content =~ ~r/<h2[^>]*>Examples<\/h2>/ do
      [{:examples, extract_code_blocks(html_content)} | sections]
    else
      sections
    end
    
    Enum.reverse(sections)
  end
  
  defp extract_text_from_tag(content, tag) do
    case Regex.run(~r/<#{tag}[^>]*>([^<]+)<\/#{tag}>/, content) do
      [_, text] -> String.trim(text)
      _ -> ""
    end
  end
  
  defp extract_summary(content) do
    case Regex.run(~r/<div class="summary">(.+?)<\/div>/s, content) do
      [_, summary] -> strip_html_tags(summary)
      _ -> "No summary available"
    end
  end
  
  defp extract_docstring(content) do
    case Regex.run(~r/<section class="docstring">(.+?)<\/section>/s, content) do
      [_, docstring] -> strip_html_tags(docstring)
      _ -> "No detailed documentation available"
    end
  end
  
  defp extract_examples(content) do
    Regex.scan(~r/<pre><code[^>]*>(.+?)<\/code><\/pre>/s, content)
    |> Enum.map(fn [_, code] -> 
      code
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&amp;", "&")
      |> String.trim()
    end)
  end
  
  defp extract_code_blocks(content) do
    Regex.scan(~r/<code[^>]*class="elixir"[^>]*>(.+?)<\/code>/s, content)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
  end
  
  defp extract_related_items(content) do
    # Extract function signatures or related modules
    functions = Regex.scan(~r/<a href="#(\w+)\/\d+">/, content)
    |> Enum.map(fn [_, func] -> func end)
    |> Enum.uniq()
    
    types = Regex.scan(~r/<a href="#t:(\w+)\/\d+">/, content)
    |> Enum.map(fn [_, type] -> "t:#{type}" end)
    |> Enum.uniq()
    
    %{
      functions: functions,
      types: types
    }
  end
  
  defp strip_html_tags(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.trim()
  end
  
  defp format_documentation(parsed_docs, params) do
    formatted = case params.format do
      "markdown" -> format_as_markdown(parsed_docs)
      "plain" -> format_as_plain_text(parsed_docs)
      "html" -> parsed_docs.raw_content
    end
    
    {:ok, formatted}
  end
  
  defp format_as_markdown(docs) do
    sections = docs.sections
    |> Enum.map(fn
      {:title, text} -> "# #{text}\n"
      {:summary, text} -> "## Summary\n\n#{text}\n"
      {:description, text} -> "## Description\n\n#{text}\n"
      {:examples, _} -> ""
    end)
    |> Enum.join("\n")
    
    examples = if docs.examples != [] do
      "\n## Examples\n\n" <>
      (docs.examples
      |> Enum.map(fn code -> "```elixir\n#{code}\n```" end)
      |> Enum.join("\n\n"))
    else
      ""
    end
    
    related = if docs.related != %{} and 
               (docs.related.functions != [] or docs.related.types != []) do
      "\n## Related\n\n" <>
      if(docs.related.functions != [], do: "**Functions:** #{Enum.join(docs.related.functions, ", ")}\n", else: "") <>
      if(docs.related.types != [], do: "**Types:** #{Enum.join(docs.related.types, ", ")}\n", else: "")
    else
      ""
    end
    
    sections <> examples <> related
  end
  
  defp format_as_plain_text(docs) do
    sections = docs.sections
    |> Enum.map(fn
      {:title, text} -> "#{String.upcase(text)}\n#{String.duplicate("=", String.length(text))}\n"
      {:summary, text} -> "SUMMARY\n-------\n#{text}\n"
      {:description, text} -> "DESCRIPTION\n-----------\n#{text}\n"
      {:examples, _} -> ""
    end)
    |> Enum.join("\n")
    
    examples = if docs.examples != [] do
      "\nEXAMPLES\n--------\n" <>
      Enum.join(docs.examples, "\n\n")
    else
      ""
    end
    
    sections <> examples
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end