defmodule RubberDuck.ProcessorTest do
  use ExUnit.Case
  import RubberDuck.ProtocolTestHelpers

  alias RubberDuck.Processor

  describe "Map implementation" do
    test "protocol is properly implemented" do
      test_protocol_implementation(
        Processor,
        Map,
        %{test: "value"},
        [:process, :metadata, :validate, :normalize]
      )
    end

    test "process with various options" do
      map = %{
        user_name: "John",
        user_email: "john@example.com",
        user_details: %{
          age: 30,
          city: "New York"
        }
      }

      test_cases = [
        # No options - returns as is
        {[], &(&1 == map)},

        # Flatten nested maps
        {[flatten: true], &Map.has_key?(&1, "user_details.age")},

        # Transform keys
        {[transform_keys: &String.replace(&1, "user_", "")],
         &(Map.has_key?(&1, :name) and not Map.has_key?(&1, :user_name))},

        # Filter keys
        {[filter_keys: [:user_name, :user_email]], &(map_size(&1) == 2 and Map.has_key?(&1, :user_name))},

        # Exclude keys
        {[exclude_keys: [:user_details]], &(not Map.has_key?(&1, :user_details))},

        # Stringify keys
        {[stringify_keys: true], &(Map.has_key?(&1, "user_name") and not Map.has_key?(&1, :user_name))},

        # Combined options
        {[flatten: true, stringify_keys: true], &(Map.has_key?(&1, "user_details.age") and is_binary(hd(Map.keys(&1))))}
      ]

      test_processor_behavior(map, test_cases)
    end

    test "metadata extraction" do
      simple_map = %{a: 1, b: 2}
      nested_map = %{a: 1, b: %{c: 2, d: %{e: 3}}}

      test_metadata_extraction(simple_map, [:type, :size, :keys, :depth])

      meta = Processor.metadata(nested_map)
      assert meta.depth == 3
      assert meta.has_nested_maps == true
    end

    test "validation" do
      assert Processor.validate(%{}) == :ok
      assert Processor.validate(%{a: 1}) == :ok
    end

    test "normalization sorts keys" do
      map = %{z: 1, a: 2, m: 3}
      normalized = Processor.normalize(map)

      assert Map.keys(normalized) == [:a, :m, :z]
    end
  end

  describe "String implementation" do
    test "protocol is properly implemented" do
      test_protocol_implementation(
        Processor,
        BitString,
        "test string",
        [:process, :metadata, :validate, :normalize]
      )
    end

    test "process with various options" do
      string = "  Hello WORLD  \r\n  Line 2  "

      test_cases = [
        # Default normalization
        {[], &(&1 == "Hello WORLD Line 2")},

        # No normalization, no trim
        {[normalize: false, trim: false], &(&1 == string)},

        # Case conversion
        {[downcase: true], &(&1 == "hello world line 2")},
        {[upcase: true], &(&1 == "HELLO WORLD LINE 2")},

        # Splitting
        {[split: :lines], &(&1 == ["Hello WORLD", "Line 2"])},
        {[split: " "], &(length(&1) == 4)},

        # Truncation
        {[max_length: 10], &(&1 == "Hello W...")},

        # Format conversion
        {[format: :code], &String.starts_with?(&1, "```")},

        # Combined with split
        {[split: :lines, max_length: 1], &(length(&1) == 1)}
      ]

      test_processor_behavior(string, test_cases)
    end

    test "metadata extraction" do
      string = "Hello\nWorld"
      unicode_string = "Hello 世界"

      test_metadata_extraction(string, [
        :type,
        :encoding,
        :byte_size,
        :character_count,
        :line_count,
        :word_count,
        :has_unicode
      ])

      meta = Processor.metadata(unicode_string)
      assert meta.has_unicode == true
      assert meta.language_hint != :unknown
    end

    test "validation" do
      test_validation_behavior(
        ["valid string", ""],
        [123, nil, :atom]
      )
    end

    test "normalization" do
      test_normalization_behavior([
        {"  spaced  ", "spaced"},
        {"line1\r\nline2", "line1 line2"},
        {"multiple  spaces", "multiple spaces"}
      ])
    end

    test "language detection" do
      elixir_code = "def hello do\n  IO.puts(\"Hello\")\nend"

      {:ok, processed} = Processor.process(elixir_code)
      meta = Processor.metadata(elixir_code)

      assert meta.language_hint == :elixir
    end
  end

  describe "List implementation" do
    test "protocol is properly implemented" do
      test_protocol_implementation(
        Processor,
        List,
        [1, 2, 3],
        [:process, :metadata, :validate, :normalize]
      )
    end

    test "process with various options" do
      list = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3]

      test_cases = [
        # No options
        {[], &(&1 == list)},

        # Filtering
        {[filter: &(&1 > 3)], &Enum.all?(&1, fn x -> x > 3 end)},

        # Mapping
        {[map: &(&1 * 2)], &(List.first(&1) == 6)},

        # Unique values
        {[unique: true], &(length(&1) == length(Enum.uniq(list)))},

        # Sorting
        {[sort: true], &(&1 == Enum.sort(list))},
        {[sort: :desc], &(&1 == Enum.sort(list, :desc))},

        # Chunking
        {[chunk_size: 3], &(is_list(List.first(&1)) and length(List.first(&1)) == 3)},

        # Limiting
        {[limit: 5], &(length(&1) == 5)},

        # Sampling
        {[sample: 3], &(length(&1) == 3)},

        # Flattening
        # Already flat
        {[flatten: true], &(&1 == list)},

        # Combined operations
        {[filter: &(&1 > 2), sort: true, unique: true], &(&1 == [3, 4, 5, 6, 9])}
      ]

      test_processor_behavior(list, test_cases)
    end

    test "process nested lists" do
      nested = [[1, 2], [3, 4], [5, 6]]

      {:ok, flattened} = Processor.process(nested, flatten: true)
      assert flattened == [1, 2, 3, 4, 5, 6]

      {:ok, deep_flattened} = Processor.process([[[1]], [[2]], [[3]]], flatten: 2)
      assert deep_flattened == [1, 2, 3]
    end

    test "batch processing" do
      list = Enum.to_list(1..20)

      batch_fn = fn batch ->
        # Sum each batch
        [Enum.sum(batch)]
      end

      {:ok, processed} = Processor.process(list, batch_process: {batch_fn, 5})
      # 4 batches of 5: [15, 40, 65, 90]
      assert processed == [15, 40, 65, 90]
    end

    test "metadata extraction" do
      mixed_list = [1, "string", %{key: "value"}, [1, 2]]

      test_metadata_extraction(mixed_list, [
        :type,
        :length,
        :empty,
        :element_types,
        :has_nested_lists,
        :max_depth
      ])

      meta = Processor.metadata(mixed_list)
      assert meta.has_nested_lists == true
      assert meta.max_depth == 2
      assert map_size(meta.element_types) == 4
    end

    test "validation" do
      assert Processor.validate([]) == :ok
      assert Processor.validate([1, 2, 3]) == :ok
      assert Processor.validate([nil, "mixed", %{}]) == :ok
    end

    test "normalization removes single-element nesting" do
      list = [[1], 2, [3], [4, 5], [6]]
      normalized = Processor.normalize(list)

      assert normalized == [1, 2, 3, [4, 5], 6]
    end
  end

  describe "error handling" do
    test "string processor handles non-strings" do
      assert {:error, :not_a_string} = Processor.process(123)
      assert {:error, :not_a_string} = Processor.process(:atom)
    end

    test "processors handle exceptions gracefully" do
      # Create a map that will cause issues
      problem_map = %{a: 1}

      # This should not crash
      result = Processor.process(problem_map, transform_keys: fn _ -> raise "oops" end)
      assert match?({:error, _}, result)
    end
  end

  describe "performance" do
    @tag :performance
    test "processing large datasets" do
      large_list = generate_test_data(:list, size: :large)
      large_map = generate_test_data(:map, size: :medium, depth: 3)
      large_string = generate_test_data(:string, size: :large)

      results =
        benchmark_protocol_operations(Processor, large_list, [
          {:process, fn p, d -> p.process(d) end},
          {:metadata, fn p, d -> p.metadata(d) end},
          {:normalize, fn p, d -> p.normalize(d) end}
        ])

      # Just ensure operations complete in reasonable time
      Enum.each(results, fn {op, time} ->
        assert time < 1000, "Operation #{op} took too long: #{time}ms"
      end)
    end
  end
end
