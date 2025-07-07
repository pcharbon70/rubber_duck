defmodule RubberDuck.ExamplePlugins do
  @moduledoc """
  Example plugin configurations and implementations for testing.
  """

  defmodule TextEnhancer do
    @moduledoc "Example plugin that enhances text"

    @behaviour RubberDuck.Plugin

    @impl true
    def name, do: :text_enhancer

    @impl true
    def version, do: "1.0.0"

    @impl true
    def description, do: "Enhances text by adding prefixes and suffixes"

    @impl true
    def supported_types, do: [:text, :any]

    @impl true
    def dependencies, do: []

    @impl true
    def init(config) do
      state = %{
        prefix: Keyword.get(config, :prefix, "["),
        suffix: Keyword.get(config, :suffix, "]")
      }

      {:ok, state}
    end

    @impl true
    def execute(input, state) when is_binary(input) do
      enhanced = "#{state.prefix}#{input}#{state.suffix}"
      {:ok, enhanced, state}
    end

    def execute(_input, state) do
      {:error, :invalid_input_type, state}
    end

    @impl true
    def terminate(_reason, _state) do
      :ok
    end

    @impl true
    def validate_input(input) do
      if is_binary(input), do: :ok, else: {:error, :not_a_string}
    end
  end

  defmodule WordCounter do
    @moduledoc "Example plugin that counts words"

    @behaviour RubberDuck.Plugin

    @impl true
    def name, do: :word_counter

    @impl true
    def version, do: "1.0.0"

    @impl true
    def description, do: "Counts words in text"

    @impl true
    def supported_types, do: [:text]

    @impl true
    def dependencies, do: []

    @impl true
    def init(_config) do
      {:ok, %{total_words_processed: 0}}
    end

    @impl true
    def execute(input, state) when is_binary(input) do
      word_count =
        input
        |> String.split(~r/\s+/)
        |> Enum.reject(&(&1 == ""))
        |> length()

      new_state = %{state | total_words_processed: state.total_words_processed + word_count}

      result = %{
        word_count: word_count,
        total_processed: new_state.total_words_processed
      }

      {:ok, result, new_state}
    end

    def execute(_input, state) do
      {:error, :invalid_input, state}
    end

    @impl true
    def terminate(_reason, _state) do
      :ok
    end
  end

  defmodule TextProcessor do
    @moduledoc "Example plugin that depends on other plugins"

    @behaviour RubberDuck.Plugin

    @impl true
    def name, do: :text_processor

    @impl true
    def version, do: "1.0.0"

    @impl true
    def description, do: "Processes text using other plugins"

    @impl true
    def supported_types, do: [:text]

    @impl true
    def dependencies, do: [:text_enhancer, :word_counter]

    @impl true
    def init(config) do
      {:ok, %{config: config}}
    end

    @impl true
    def execute(input, state) when is_binary(input) do
      # This plugin would normally communicate with its dependencies
      # via the MessageBus
      processed = String.upcase(input)
      {:ok, processed, state}
    end

    def execute(_input, state) do
      {:error, :invalid_input, state}
    end

    @impl true
    def terminate(_reason, _state) do
      :ok
    end
  end
end
