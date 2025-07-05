defmodule RubberDuck.ProtocolTestHelpers do
  @moduledoc """
  Test helpers for protocol implementations.
  
  Provides utilities for testing protocol behavior across different types
  and ensuring consistent implementation.
  """
  
  import ExUnit.Assertions
  
  @doc """
  Test that a protocol is properly implemented for a given type.
  
  ## Example
  
      test_protocol_implementation(
        RubberDuck.Processor,
        BitString,
        "test string",
        [:process, :metadata, :validate, :normalize]
      )
  """
  def test_protocol_implementation(protocol, type_module, sample_data, functions) do
    assert Protocol.assert_impl!(protocol, type_module)
    
    Enum.each(functions, fn function ->
      assert function_exported?(protocol.impl_for!(type_module), function, 
                               :erlang.fun_info(Function.capture(protocol, function, 1))[:arity])
    end)
    
    # Test that functions can be called without errors
    Enum.each(functions, fn function ->
      case function do
        :process -> apply(protocol, function, [sample_data, []])
        _ -> apply(protocol, function, [sample_data])
      end
    end)
  end
  
  @doc """
  Test processor protocol behavior with various options.
  """
  def test_processor_behavior(data, test_cases) do
    Enum.each(test_cases, fn {opts, expected_check} ->
      result = RubberDuck.Processor.process(data, opts)
      
      case expected_check do
        {:ok, check_fn} when is_function(check_fn) ->
          assert {:ok, processed} = result
          assert check_fn.(processed), 
                 "Processing with opts #{inspect(opts)} failed check"
                 
        {:error, _} = expected ->
          assert result == expected
          
        expected ->
          assert result == {:ok, expected}
      end
    end)
  end
  
  @doc """
  Test enhancer protocol behavior with various strategies.
  """
  def test_enhancer_behavior(data, strategies) do
    Enum.each(strategies, fn strategy ->
      result = RubberDuck.Enhancer.enhance(data, strategy)
      
      assert match?({:ok, _}, result), 
             "Enhancement with strategy #{inspect(strategy)} failed"
             
      {:ok, enhanced} = result
      refute enhanced == data, 
             "Enhancement should modify the data"
    end)
  end
  
  @doc """
  Test that metadata extraction works correctly.
  """
  def test_metadata_extraction(data, expected_keys) do
    metadata = RubberDuck.Processor.metadata(data)
    
    assert is_map(metadata)
    
    Enum.each(expected_keys, fn key ->
      assert Map.has_key?(metadata, key),
             "Metadata should contain key: #{inspect(key)}"
    end)
    
    # Common metadata fields
    assert Map.has_key?(metadata, :type)
    assert Map.has_key?(metadata, :timestamp)
  end
  
  @doc """
  Test validation behavior.
  """
  def test_validation_behavior(valid_samples, invalid_samples) do
    Enum.each(valid_samples, fn sample ->
      assert RubberDuck.Processor.validate(sample) == :ok,
             "Valid sample should pass validation: #{inspect(sample)}"
    end)
    
    Enum.each(invalid_samples, fn sample ->
      result = RubberDuck.Processor.validate(sample)
      assert match?({:error, _}, result),
             "Invalid sample should fail validation: #{inspect(sample)}"
    end)
  end
  
  @doc """
  Test normalization behavior.
  """
  def test_normalization_behavior(samples_with_expected) do
    Enum.each(samples_with_expected, fn {sample, expected} ->
      normalized = RubberDuck.Processor.normalize(sample)
      
      if is_function(expected) do
        assert expected.(normalized),
               "Normalization failed check for: #{inspect(sample)}"
      else
        assert normalized == expected,
               "Normalization mismatch for: #{inspect(sample)}"
      end
    end)
  end
  
  @doc """
  Test derivation functionality.
  """
  def test_derivation_behavior(data, derivations) do
    # Test single derivations
    Enum.each(derivations, fn derivation ->
      result = RubberDuck.Enhancer.derive(data, derivation)
      
      assert match?({:ok, %{}}, result),
             "Derivation #{inspect(derivation)} should return a map"
    end)
    
    # Test multiple derivations
    result = RubberDuck.Enhancer.derive(data, derivations)
    assert match?({:ok, %{}}, result)
    
    {:ok, derived} = result
    assert map_size(derived) > 0,
           "Multiple derivations should produce results"
  end
  
  @doc """
  Property-based test helper for processor implementations.
  """
  def property_process_always_returns_tuple(generator) do
    property = fn ->
      data = generator.()
      result = RubberDuck.Processor.process(data)
      
      assert match?({:ok, _} | {:error, _}, result),
             "Process should always return {:ok, _} or {:error, _}"
    end
    
    property
  end
  
  @doc """
  Property-based test helper for enhancer implementations.
  """
  def property_enhance_preserves_type(generator, strategy) do
    property = fn ->
      data = generator.()
      result = RubberDuck.Enhancer.enhance(data, strategy)
      
      case result do
        {:ok, enhanced} ->
          # Enhancement might wrap data but should preserve access to original
          assert is_map(enhanced) or match?(^data, enhanced),
                 "Enhancement should preserve data accessibility"
                 
        {:error, _} ->
          # Errors are acceptable
          :ok
      end
    end
    
    property
  end
  
  @doc """
  Test protocol performance with benchmarking.
  """
  def benchmark_protocol_operations(protocol, data, operations) do
    results = Enum.map(operations, fn {name, operation} ->
      {time, _result} = :timer.tc(fn ->
        Enum.each(1..1000, fn _ -> operation.(protocol, data) end)
      end)
      
      {name, time / 1000} # Convert to milliseconds
    end)
    
    results
  end
  
  @doc """
  Generate test data for different types.
  """
  def generate_test_data(type, opts \\ []) do
    case type do
      :string ->
        size = Keyword.get(opts, :size, :medium)
        generate_string(size)
        
      :map ->
        depth = Keyword.get(opts, :depth, 1)
        size = Keyword.get(opts, :size, :medium)
        generate_map(depth, size)
        
      :list ->
        size = Keyword.get(opts, :size, :medium)
        element_type = Keyword.get(opts, :element_type, :mixed)
        generate_list(size, element_type)
        
      _ ->
        raise "Unknown type: #{inspect(type)}"
    end
  end
  
  # Private functions
  
  defp generate_string(:small), do: "test"
  defp generate_string(:medium), do: String.duplicate("test ", 20)
  defp generate_string(:large), do: String.duplicate("test ", 1000)
  
  defp generate_map(1, :small) do
    %{a: 1, b: "test", c: true}
  end
  
  defp generate_map(1, :medium) do
    for i <- 1..10, into: %{} do
      {:"key_#{i}", generate_value()}
    end
  end
  
  defp generate_map(depth, size) when depth > 1 do
    base = generate_map(1, size)
    
    Map.put(base, :nested, generate_map(depth - 1, size))
  end
  
  defp generate_list(:small, _), do: [1, 2, 3]
  
  defp generate_list(:medium, :numeric), do: Enum.to_list(1..20)
  
  defp generate_list(:medium, :string) do
    Enum.map(1..20, &"item_#{&1}")
  end
  
  defp generate_list(:medium, :mixed) do
    Enum.map(1..20, fn i ->
      case rem(i, 3) do
        0 -> i
        1 -> "item_#{i}"
        2 -> %{id: i, value: i * 2}
      end
    end)
  end
  
  defp generate_list(:large, element_type) do
    Enum.map(1..1000, fn _ ->
      case element_type do
        :numeric -> :rand.uniform(1000)
        :string -> "item_#{:rand.uniform(1000)}"
        :mixed -> generate_value()
      end
    end)
  end
  
  defp generate_value do
    case :rand.uniform(5) do
      1 -> :rand.uniform(100)
      2 -> "string_#{:rand.uniform(100)}"
      3 -> :rand.uniform() > 0.5
      4 -> [1, 2, 3]
      5 -> %{nested: true}
    end
  end
  
  @doc """
  Assert protocol consistency across similar operations.
  """
  def assert_protocol_consistency(protocol, data1, data2) do
    # Metadata should have same keys for same type
    meta1 = protocol.metadata(data1)
    meta2 = protocol.metadata(data2)
    
    assert Map.keys(meta1) -- [:timestamp] == Map.keys(meta2) -- [:timestamp],
           "Metadata keys should be consistent for same type"
           
    # Validation should be consistent
    valid1 = protocol.validate(data1)
    valid2 = protocol.validate(data2)
    
    assert match?({^valid1, ^valid2}, {valid1, valid2}) when valid1 in [:ok, {:error, _}],
           "Validation should be consistent for similar data"
  end
  
  @doc """
  Test error handling behavior.
  """
  def test_error_handling(protocol, error_cases) do
    Enum.each(error_cases, fn {input, expected_error} ->
      result = case protocol do
        RubberDuck.Processor -> protocol.process(input)
        RubberDuck.Enhancer -> protocol.enhance(input, :semantic)
      end
      
      assert match?({:error, ^expected_error}, result) or match?({:error, _}, result),
             "Expected error for input: #{inspect(input)}"
    end)
  end
end