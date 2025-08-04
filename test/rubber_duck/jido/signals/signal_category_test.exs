defmodule RubberDuck.Jido.Signals.SignalCategoryTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Signals.SignalCategory
  
  describe "categories/0" do
    test "returns all signal categories" do
      categories = SignalCategory.categories()
      
      assert :request in categories
      assert :event in categories
      assert :command in categories
      assert :query in categories
      assert :notification in categories
      assert length(categories) == 5
    end
  end
  
  describe "valid_category?/1" do
    test "validates known categories" do
      assert SignalCategory.valid_category?(:request)
      assert SignalCategory.valid_category?(:event)
      assert SignalCategory.valid_category?(:command)
      assert SignalCategory.valid_category?(:query)
      assert SignalCategory.valid_category?(:notification)
    end
    
    test "rejects invalid categories" do
      refute SignalCategory.valid_category?(:invalid)
      refute SignalCategory.valid_category?("request")
      refute SignalCategory.valid_category?(nil)
    end
  end
  
  describe "category_definition/1" do
    test "returns definitions for each category" do
      assert SignalCategory.category_definition(:request) =~ "initiate"
      assert SignalCategory.category_definition(:event) =~ "happened"
      assert SignalCategory.category_definition(:command) =~ "command"
      assert SignalCategory.category_definition(:query) =~ "information"
      assert SignalCategory.category_definition(:notification) =~ "alerts"
    end
  end
  
  describe "infer_category/1" do
    test "infers request category" do
      assert {:ok, :request} = SignalCategory.infer_category("analysis.request")
      assert {:ok, :request} = SignalCategory.infer_category("user.request.create")
      assert {:ok, :request} = SignalCategory.infer_category("system.initiate")
    end
    
    test "infers event category" do
      assert {:ok, :event} = SignalCategory.infer_category("user.created")
      assert {:ok, :event} = SignalCategory.infer_category("order.updated")
      assert {:ok, :event} = SignalCategory.infer_category("file.deleted")
      assert {:ok, :event} = SignalCategory.infer_category("process.completed")
    end
    
    test "infers command category" do
      assert {:ok, :command} = SignalCategory.infer_category("server.execute")
      assert {:ok, :command} = SignalCategory.infer_category("process.stop")
      assert {:ok, :command} = SignalCategory.infer_category("job.cancel")
    end
    
    test "infers query category" do
      assert {:ok, :query} = SignalCategory.infer_category("user.query")
      assert {:ok, :query} = SignalCategory.infer_category("data.fetch")
      assert {:ok, :query} = SignalCategory.infer_category("records.list")
    end
    
    test "infers notification category" do
      assert {:ok, :notification} = SignalCategory.infer_category("system.alert")
      assert {:ok, :notification} = SignalCategory.infer_category("health.warning")
      assert {:ok, :notification} = SignalCategory.infer_category("status.notify")
    end
    
    test "returns error for unknown patterns" do
      assert {:error, :unknown_category} = SignalCategory.infer_category("unknown.type")
      assert {:error, :unknown_category} = SignalCategory.infer_category("random")
    end
  end
  
  describe "default_priority/1" do
    test "returns appropriate priorities" do
      assert SignalCategory.default_priority(:request) == :normal
      assert SignalCategory.default_priority(:event) == :normal
      assert SignalCategory.default_priority(:command) == :high
      assert SignalCategory.default_priority(:query) == :low
      assert SignalCategory.default_priority(:notification) == :normal
    end
  end
  
  describe "create_signal_spec/3" do
    test "creates a signal specification" do
      spec = SignalCategory.create_signal_spec("user.created", :event)
      
      assert spec.category == :event
      assert spec.domain == "user"
      assert spec.action == "created"
      assert spec.priority == :normal
      assert spec.routing_key == "user.event"
      assert spec.metadata == %{}
    end
    
    test "accepts custom options" do
      spec = SignalCategory.create_signal_spec(
        "critical.alert",
        :notification,
        priority: :critical,
        routing_key: "alerts.critical",
        metadata: %{severity: "high"}
      )
      
      assert spec.priority == :critical
      assert spec.routing_key == "alerts.critical"
      assert spec.metadata == %{severity: "high"}
    end
  end
  
  describe "validate_signal_spec/1" do
    test "validates a complete spec" do
      spec = %{
        category: :request,
        domain: "user",
        action: "create",
        priority: :normal,
        routing_key: "user.request",
        metadata: %{}
      }
      
      assert {:ok, ^spec} = SignalCategory.validate_signal_spec(spec)
    end
    
    test "rejects spec with missing fields" do
      spec = %{
        category: :request,
        domain: "user"
      }
      
      assert {:error, {:missing_fields, _}} = SignalCategory.validate_signal_spec(spec)
    end
    
    test "rejects spec with invalid category" do
      spec = %{
        category: :invalid,
        domain: "user",
        action: "create",
        priority: :normal,
        routing_key: "user.request",
        metadata: %{}
      }
      
      assert {:error, {:invalid_category, :invalid}} = SignalCategory.validate_signal_spec(spec)
    end
    
    test "rejects spec with invalid priority" do
      spec = %{
        category: :request,
        domain: "user",
        action: "create",
        priority: :extreme,
        routing_key: "user.request",
        metadata: %{}
      }
      
      assert {:error, {:invalid_priority, :extreme}} = SignalCategory.validate_signal_spec(spec)
    end
  end
end