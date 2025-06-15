defmodule RubberDuck.Interface.BehaviourTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.Behaviour
  
  describe "generate_request_id/0" do
    test "generates unique request IDs" do
      id1 = Behaviour.generate_request_id()
      id2 = Behaviour.generate_request_id()
      
      assert id1 != id2
      assert String.starts_with?(id1, "req_")
      assert String.contains?(id1, "_")
    end
    
    test "request IDs contain timestamp" do
      id = Behaviour.generate_request_id()
      parts = String.split(id, "_")
      
      assert length(parts) == 3
      assert parts |> Enum.at(2) |> String.to_integer() > 0
    end
  end
  
  describe "error/3" do
    test "creates standard error tuple with metadata" do
      error = Behaviour.error(:validation_error, "Invalid input", %{field: "name"})
      
      assert {:error, :validation_error, "Invalid input", %{field: "name"}} = error
    end
    
    test "creates standard error tuple without metadata" do
      error = Behaviour.error(:timeout, "Request timed out")
      
      assert {:error, :timeout, "Request timed out", %{}} = error
    end
    
    test "converts non-string messages to string" do
      error = Behaviour.error(:internal_error, :atom_message)
      
      assert {:error, :internal_error, "atom_message", %{}} = error
    end
  end
  
  describe "success_response/3" do
    test "creates successful response with timestamp" do
      response = Behaviour.success_response("req_123", %{result: "data"})
      
      assert %{
        id: "req_123",
        status: :ok,
        data: %{result: "data"},
        metadata: %{},
        timestamp: timestamp
      } = response
      
      assert %DateTime{} = timestamp
    end
    
    test "includes custom metadata" do
      response = Behaviour.success_response("req_123", "data", %{custom: "meta"})
      
      assert response.metadata == %{custom: "meta"}
    end
  end
  
  describe "error_response/3" do
    test "creates error response with timestamp" do
      error = {:error, :not_found, "Resource not found", %{}}
      response = Behaviour.error_response("req_123", error)
      
      assert %{
        id: "req_123",
        status: :error,
        data: ^error,
        metadata: %{},
        timestamp: timestamp
      } = response
      
      assert %DateTime{} = timestamp
    end
  end
  
  describe "behaviour compliance" do
    defmodule TestAdapter do
      @behaviour RubberDuck.Interface.Behaviour
      
      @impl true
      def init(_opts), do: {:ok, %{}}
      
      @impl true
      def handle_request(_request, _context, state), do: {:ok, %{}, state}
      
      @impl true
      def format_response(_response, _request, _state), do: {:ok, %{}}
      
      @impl true
      def handle_error(_error, _request, _state), do: %{}
      
      @impl true
      def capabilities(), do: [:chat, :complete]
      
      @impl true
      def validate_request(_request), do: :ok
      
      @impl true
      def shutdown(_reason, _state), do: :ok
    end
    
    test "adapter implements all required callbacks" do
      assert function_exported?(TestAdapter, :init, 1)
      assert function_exported?(TestAdapter, :handle_request, 3)
      assert function_exported?(TestAdapter, :format_response, 3)
      assert function_exported?(TestAdapter, :handle_error, 3)
      assert function_exported?(TestAdapter, :capabilities, 0)
      assert function_exported?(TestAdapter, :validate_request, 1)
      assert function_exported?(TestAdapter, :shutdown, 2)
    end
  end
end