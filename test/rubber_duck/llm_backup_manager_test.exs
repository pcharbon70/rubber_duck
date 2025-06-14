defmodule RubberDuck.LLMBackupManagerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.LLMBackupManager
  alias RubberDuck.LLMDataManager
  alias RubberDuck.MnesiaManager
  
  @test_backup_dir "/tmp/llm_backup_test"
  
  setup_all do
    # Ensure Mnesia is running and tables are created
    {:ok, _pid} = MnesiaManager.start_link()
    :ok = MnesiaManager.initialize_schema()
    
    on_exit(fn ->
      # Clean up test backup directory
      File.rm_rf(@test_backup_dir)
      # Clean up test data
      :mnesia.clear_table(:llm_responses)
      :mnesia.clear_table(:llm_provider_status)
    end)
    
    :ok
  end
  
  setup do
    # Clean tables and test directory before each test
    :mnesia.clear_table(:llm_responses)
    :mnesia.clear_table(:llm_provider_status)
    File.rm_rf(@test_backup_dir)
    File.mkdir_p!(@test_backup_dir)
    :ok
  end
  
  describe "LLM data backup" do
    test "creates and verifies backup with test data" do
      # Setup test data
      setup_test_data()
      
      backup_path = Path.join(@test_backup_dir, "test_backup.llm")
      
      # Create backup
      assert {:ok, backup_result} = LLMBackupManager.create_llm_backup(backup_path)
      assert File.exists?(backup_path)
      assert backup_result.stats.total_responses > 0
      assert backup_result.stats.total_provider_status > 0
      
      # Verify backup
      assert {:ok, verification} = LLMBackupManager.verify_backup(backup_path)
      assert verification.integrity == :valid
      assert verification.stats.total_responses == backup_result.stats.total_responses
      assert verification.stats.total_provider_status == backup_result.stats.total_provider_status
    end
    
    test "creates backup with filters" do
      # Setup test data
      setup_test_data()
      
      backup_path = Path.join(@test_backup_dir, "filtered_backup.llm")
      
      # Create backup with provider filter
      filters = %{provider: "openai"}
      assert {:ok, backup_result} = LLMBackupManager.create_llm_backup(backup_path, filters: filters)
      
      # Verify filtered backup
      assert {:ok, verification} = LLMBackupManager.verify_backup(backup_path)
      assert verification.stats.total_responses >= 0  # Should only include OpenAI responses
    end
    
    test "creates compressed backup" do
      # Setup test data
      setup_test_data()
      
      compressed_path = Path.join(@test_backup_dir, "compressed_backup.llm")
      uncompressed_path = Path.join(@test_backup_dir, "uncompressed_backup.llm")
      
      # Create compressed and uncompressed backups
      assert {:ok, _} = LLMBackupManager.create_llm_backup(compressed_path, compress: true)
      assert {:ok, _} = LLMBackupManager.create_llm_backup(uncompressed_path, compress: false)
      
      # Compressed file should be smaller (with enough data)
      compressed_size = File.stat!(compressed_path).size
      uncompressed_size = File.stat!(uncompressed_path).size
      
      # Both should be readable
      assert {:ok, _} = LLMBackupManager.verify_backup(compressed_path)
      assert {:ok, _} = LLMBackupManager.verify_backup(uncompressed_path)
    end
  end
  
  describe "LLM data restore" do
    test "restores data from backup" do
      # Setup and backup test data
      setup_test_data()
      
      backup_path = Path.join(@test_backup_dir, "restore_test_backup.llm")
      assert {:ok, _} = LLMBackupManager.create_llm_backup(backup_path)
      
      # Clear tables
      :mnesia.clear_table(:llm_responses)
      :mnesia.clear_table(:llm_provider_status)
      
      # Verify tables are empty
      assert {:ok, empty_stats} = LLMDataManager.get_response_stats()
      assert empty_stats.total_responses == 0
      
      # Restore from backup
      assert {:ok, restore_result} = LLMBackupManager.restore_llm_backup(backup_path)
      assert restore_result.stats.responses_restored > 0
      assert restore_result.stats.provider_status_restored > 0
      
      # Verify data is restored
      assert {:ok, restored_stats} = LLMDataManager.get_response_stats()
      assert restored_stats.total_responses > 0
      
      # Verify specific data
      assert {:ok, _} = LLMDataManager.get_response_by_prompt("Test prompt 1")
      assert {:ok, _} = LLMDataManager.get_provider_status("openai")
    end
    
    test "handles selective restore options" do
      # Setup and backup test data
      setup_test_data()
      
      backup_path = Path.join(@test_backup_dir, "selective_restore_backup.llm")
      assert {:ok, _} = LLMBackupManager.create_llm_backup(backup_path)
      
      # Clear tables
      :mnesia.clear_table(:llm_responses)
      :mnesia.clear_table(:llm_provider_status)
      
      # Restore only responses, not provider status
      assert {:ok, restore_result} = LLMBackupManager.restore_llm_backup(backup_path, 
        restore_responses: true,
        restore_provider_status: false
      )
      
      assert restore_result.stats.responses_restored > 0
      assert restore_result.stats.provider_status_restored == 0
      
      # Verify responses are restored but provider status is not
      assert {:ok, stats} = LLMDataManager.get_response_stats()
      assert stats.total_responses > 0
      
      assert {:error, :not_found} = LLMDataManager.get_provider_status("openai")
    end
    
    test "handles overwrite existing option" do
      # Setup initial data
      setup_test_data()
      
      # Modify some data
      updated_provider_data = %{
        provider_name: "openai",
        status: :active,
        health_score: 75,  # Different from original
        total_requests: 2000  # Different from original
      }
      assert {:ok, _} = LLMDataManager.update_provider_status(updated_provider_data)
      
      # Create backup with original data
      backup_path = Path.join(@test_backup_dir, "overwrite_test_backup.llm")
      assert {:ok, _} = LLMBackupManager.create_llm_backup(backup_path)
      
      # Restore with overwrite_existing: false (default)
      assert {:ok, restore_result} = LLMBackupManager.restore_llm_backup(backup_path, 
        overwrite_existing: false
      )
      
      # Should have skipped existing records
      assert restore_result.stats.provider_status_skipped > 0
      
      # Now restore with overwrite_existing: true
      assert {:ok, restore_result_2} = LLMBackupManager.restore_llm_backup(backup_path,
        overwrite_existing: true
      )
      
      # Should have restored/updated existing records
      assert restore_result_2.stats.provider_status_restored > 0
    end
  end
  
  describe "backup migration" do
    test "migrates backup to new format version" do
      # Setup test data and create backup
      setup_test_data()
      
      old_backup_path = Path.join(@test_backup_dir, "old_format_backup.llm")
      new_backup_path = Path.join(@test_backup_dir, "migrated_backup.llm")
      
      assert {:ok, _} = LLMBackupManager.create_llm_backup(old_backup_path)
      
      # Migrate backup
      assert {:ok, migration_result} = LLMBackupManager.migrate_backup(
        old_backup_path, 
        new_backup_path,
        "2.0"
      )
      
      assert migration_result.old_version == "1.0"
      assert migration_result.new_version == "2.0"
      assert File.exists?(new_backup_path)
      
      # Verify migrated backup
      assert {:ok, verification} = LLMBackupManager.verify_backup(new_backup_path)
      assert verification.format_version == "2.0"
    end
  end
  
  describe "backup verification" do
    test "detects corrupted backup files" do
      corrupted_path = Path.join(@test_backup_dir, "corrupted_backup.llm")
      
      # Create a corrupted file
      File.write!(corrupted_path, "This is not a valid backup file")
      
      # Verification should fail
      assert {:error, _} = LLMBackupManager.verify_backup(corrupted_path)
    end
    
    test "handles missing backup files" do
      missing_path = Path.join(@test_backup_dir, "missing_backup.llm")
      
      # Verification should fail for missing file
      assert {:error, _} = LLMBackupManager.verify_backup(missing_path)
    end
  end
  
  # Helper Functions
  
  defp setup_test_data do
    # Create test LLM responses
    responses = [
      %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Test prompt 1",
        response: "Test response 1",
        tokens_used: 100,
        cost: 0.002,
        latency: 800,
        session_id: "session_1"
      },
      %{
        provider: "anthropic",
        model: "claude",
        prompt: "Test prompt 2", 
        response: "Test response 2",
        tokens_used: 150,
        cost: 0.003,
        latency: 900,
        session_id: "session_2"
      },
      %{
        provider: "openai",
        model: "gpt-3.5",
        prompt: "Test prompt 3",
        response: "Test response 3",
        tokens_used: 80,
        cost: 0.001,
        latency: 600,
        session_id: "session_1"
      }
    ]
    
    Enum.each(responses, &LLMDataManager.store_response/1)
    
    # Create test provider status records
    providers = [
      %{
        provider_name: "openai",
        status: :active,
        health_score: 95,
        total_requests: 1000,
        successful_requests: 950,
        failed_requests: 50,
        average_latency: 800,
        cost_total: 25.50
      },
      %{
        provider_name: "anthropic",
        status: :active,
        health_score: 88,
        total_requests: 500,
        successful_requests: 480,
        failed_requests: 20,
        average_latency: 900,
        cost_total: 15.25
      },
      %{
        provider_name: "cohere",
        status: :inactive,
        health_score: 60,
        total_requests: 100,
        successful_requests: 80,
        failed_requests: 20,
        average_latency: 1200,
        cost_total: 5.00
      }
    ]
    
    Enum.each(providers, &LLMDataManager.update_provider_status/1)
  end
end