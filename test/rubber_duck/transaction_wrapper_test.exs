defmodule RubberDuck.TransactionWrapperTest do
  use ExUnit.Case, async: false

  alias RubberDuck.{TransactionWrapper, MnesiaManager}

  setup do
    # Stop the application to control lifecycle in tests
    Application.stop(:rubber_duck)
    
    # Clean up any existing Mnesia schema
    :mnesia.delete_schema([node()])
    
    on_exit(fn -> 
      :mnesia.stop()
      :mnesia.delete_schema([node()])
      Application.start(:rubber_duck) 
    end)
    
    # Start Mnesia and initialize schema
    {:ok, _} = MnesiaManager.start_link([])
    MnesiaManager.initialize_schema()
    
    :ok
  end

  describe "read_transaction/2" do
    test "executes read operations successfully" do
      transaction_fun = fn ->
        :mnesia.table_info(:sessions, :size)
      end

      assert {:ok, _size} = TransactionWrapper.read_transaction(transaction_fun)
    end

    test "handles read failures with retry" do
      call_count = Agent.start_link(fn -> 0 end)
      
      transaction_fun = fn ->
        count = Agent.get_and_update(call_count, &{&1, &1 + 1})
        if count < 2 do
          :mnesia.abort(:simulated_failure)
        else
          42
        end
      end

      assert {:ok, 42} = TransactionWrapper.read_transaction(transaction_fun, retries: 3)
    end
  end

  describe "write_transaction/4" do
    test "creates new records successfully" do
      record = %{
        session_id: "test_session",
        messages: [],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }

      assert {:ok, _} = TransactionWrapper.write_transaction(:sessions, :create, record, broadcast: false)
      
      # Verify record was created
      {:ok, records} = TransactionWrapper.read_records(:sessions, {:id, "test_session"})
      assert length(records) == 1
    end

    test "updates existing records" do
      # First create a record
      record = %{
        session_id: "update_test",
        messages: [],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }
      
      TransactionWrapper.write_transaction(:sessions, :create, record, broadcast: false)
      
      # Then update it
      updated_record = Map.put(record, :messages, ["hello"])
      assert {:ok, _} = TransactionWrapper.write_transaction(:sessions, :update, updated_record, broadcast: false)
    end

    test "deletes records" do
      # First create a record
      record = %{
        session_id: "delete_test",
        messages: [],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }
      
      TransactionWrapper.write_transaction(:sessions, :create, record, broadcast: false)
      
      # Then delete it
      assert {:ok, _} = TransactionWrapper.write_transaction(:sessions, :delete, record, broadcast: false)
      
      # Verify it's gone
      {:ok, records} = TransactionWrapper.read_records(:sessions, {:id, "delete_test"})
      assert length(records) == 0
    end
  end

  describe "create_record/3" do
    test "creates record with auto-generated ID" do
      record = %{
        messages: ["test message"],
        metadata: %{test: true},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }

      assert {:ok, created_record} = TransactionWrapper.create_record(:sessions, record, broadcast: false)
      assert Map.has_key?(created_record, :session_id)
      assert created_record.session_id != nil
    end

    test "preserves existing ID" do
      record = %{
        session_id: "existing_id",
        messages: [],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }

      assert {:ok, created_record} = TransactionWrapper.create_record(:sessions, record, broadcast: false)
      assert created_record.session_id == "existing_id"
    end
  end

  describe "update_record/4" do
    test "updates existing record successfully" do
      # Create initial record
      record = %{
        session_id: "update_test_2",
        messages: [],
        metadata: %{version: 1},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }
      
      TransactionWrapper.create_record(:sessions, record, broadcast: false)
      
      # Update the record
      updates = %{
        messages: ["new message"],
        metadata: %{version: 2}
      }
      
      assert {:ok, updated_record} = TransactionWrapper.update_record(:sessions, "update_test_2", updates, broadcast: false)
      assert updated_record.messages == ["new message"]
      assert updated_record.metadata.version == 2
    end

    test "handles non-existent record" do
      updates = %{messages: ["test"]}
      
      assert {:error, :not_found} = TransactionWrapper.update_record(:sessions, "nonexistent", updates, broadcast: false)
    end
  end

  describe "delete_record/3" do
    test "deletes existing record" do
      # Create record
      record = %{
        session_id: "delete_test_2",
        messages: [],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }
      
      TransactionWrapper.create_record(:sessions, record, broadcast: false)
      
      # Delete it
      assert {:ok, _deleted_record} = TransactionWrapper.delete_record(:sessions, "delete_test_2", broadcast: false)
      
      # Verify it's gone
      {:ok, records} = TransactionWrapper.read_records(:sessions, {:id, "delete_test_2"})
      assert length(records) == 0
    end

    test "handles non-existent record deletion" do
      assert {:error, :not_found} = TransactionWrapper.delete_record(:sessions, "nonexistent", broadcast: false)
    end
  end

  describe "read_records/3" do
    test "reads all records" do
      # Create some test records
      Enum.each(1..3, fn i ->
        record = %{
          session_id: "test_#{i}",
          messages: [],
          metadata: %{index: i},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          node: node()
        }
        TransactionWrapper.create_record(:sessions, record, broadcast: false)
      end)
      
      {:ok, records} = TransactionWrapper.read_records(:sessions, :all)
      assert length(records) >= 3
    end

    test "reads records by ID" do
      record = %{
        session_id: "read_by_id_test",
        messages: ["hello"],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }
      
      TransactionWrapper.create_record(:sessions, record, broadcast: false)
      
      {:ok, records} = TransactionWrapper.read_records(:sessions, {:id, "read_by_id_test"})
      assert length(records) == 1
    end
  end

  describe "bulk_operation/3" do
    test "performs bulk operations successfully" do
      operations = [
        {:create, %{
          session_id: "bulk_1",
          messages: [],
          metadata: %{},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          node: node()
        }},
        {:create, %{
          session_id: "bulk_2", 
          messages: [],
          metadata: %{},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          node: node()
        }}
      ]

      assert {:ok, results} = TransactionWrapper.bulk_operation(:sessions, operations, broadcast: false)
      assert length(results) == 2
    end

    test "handles bulk operation failures" do
      operations = [
        {:create, %{session_id: "bulk_3", messages: [], metadata: %{}, 
                   created_at: DateTime.utc_now(), updated_at: DateTime.utc_now(), node: node()}},
        {:invalid_operation, %{}} # This should cause failure
      ]

      assert {:error, _} = TransactionWrapper.bulk_operation(:sessions, operations, broadcast: false)
    end
  end

  describe "table_info/1" do
    test "returns table information" do
      {:ok, info} = TransactionWrapper.table_info(:sessions)
      
      assert is_map(info)
      assert Map.has_key?(info, :size)
      assert Map.has_key?(info, :type)
      assert Map.has_key?(info, :memory)
      assert Map.has_key?(info, :storage_type)
      assert Map.has_key?(info, :attributes)
    end
  end
end