defmodule RubberDuck.Interface.CapabilitiesTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.Capabilities
  
  describe "discover_capabilities/2" do
    test "discovers capabilities for CLI interface" do
      {:ok, capability_set} = Capabilities.discover_capabilities(:cli)
      
      assert capability_set.interface == :cli
      assert capability_set.source == :default
      assert is_list(capability_set.capabilities)
      assert %DateTime{} = capability_set.timestamp
      
      # Check for expected CLI capabilities
      capability_names = Enum.map(capability_set.capabilities, &Map.get(&1, :name))
      assert :chat in capability_names
      assert :file_upload in capability_names
      assert :interactive_mode in capability_names
    end
    
    test "discovers capabilities for Web interface" do
      {:ok, capability_set} = Capabilities.discover_capabilities(:web)
      
      assert capability_set.interface == :web
      capability_names = Enum.map(capability_set.capabilities, &Map.get(&1, :name))
      assert :streaming in capability_names
      assert :websocket_support in capability_names
      assert :authentication in capability_names
    end
    
    test "discovers capabilities for LSP interface" do
      {:ok, capability_set} = Capabilities.discover_capabilities(:lsp)
      
      assert capability_set.interface == :lsp
      capability_names = Enum.map(capability_set.capabilities, &Map.get(&1, :name))
      assert :completion in capability_names
      assert :hover in capability_names
      assert :diagnostics in capability_names
    end
    
    test "handles invalid interface" do
      assert {:error, :invalid_adapter_or_interface} = 
        Capabilities.discover_capabilities(:invalid)
    end
    
    test "discovers capabilities from adapter module" do
      defmodule TestAdapter do
        def capabilities, do: [:chat, :complete, :custom_feature]
      end
      
      {:ok, capability_set} = Capabilities.discover_capabilities(TestAdapter)
      
      assert capability_set.source == :adapter
      assert capability_set.module == TestAdapter
      capability_names = Enum.map(capability_set.capabilities, &Map.get(&1, :name))
      assert :chat in capability_names
      assert :complete in capability_names
      assert :custom_feature in capability_names
    end
  end
  
  describe "negotiate_capabilities/3" do
    test "negotiates common capabilities successfully" do
      client_caps = [:chat, :complete, :file_upload]
      server_caps = [:chat, :complete, :streaming, :authentication]
      
      {:ok, result} = Capabilities.negotiate_capabilities(client_caps, server_caps)
      
      assert :chat in result.agreed_capabilities
      assert :complete in result.agreed_capabilities
      refute :file_upload in result.agreed_capabilities
      refute :streaming in result.agreed_capabilities
      
      assert result.client_capabilities == client_caps
      assert result.server_capabilities == server_caps
      assert result.compatibility_level in [:full, :partial, :minimal]
    end
    
    test "handles minimum requirements" do
      client_caps = [:chat, :complete]
      server_caps = [:chat, :streaming]
      
      # Should succeed when minimum requirements are met
      {:ok, result} = Capabilities.negotiate_capabilities(
        client_caps, 
        server_caps, 
        require_minimum: [:chat]
      )
      assert :chat in result.agreed_capabilities
      
      # Should fail when minimum requirements are not met
      {:error, {:minimum_requirements_not_met, missing}} = 
        Capabilities.negotiate_capabilities(
          client_caps, 
          server_caps, 
          require_minimum: [:authentication]
        )
      assert :authentication in missing
    end
    
    test "strict mode negotiation" do
      client_caps = [:chat, :complete]
      server_caps = [:chat, :complete]
      
      {:ok, result} = Capabilities.negotiate_capabilities(
        client_caps, 
        server_caps, 
        strict_mode: true
      )
      assert result.compatibility_level == :full
      
      # Different capabilities should be incompatible in strict mode
      server_caps_different = [:chat, :streaming]
      {:ok, result} = Capabilities.negotiate_capabilities(
        client_caps, 
        server_caps_different, 
        strict_mode: true
      )
      assert result.compatibility_level == :incompatible
    end
  end
  
  describe "validate_capability/3" do
    test "validates supported operations" do
      capabilities = [:chat, :complete, :file_upload]
      
      assert :ok = Capabilities.validate_capability(:chat, capabilities)
      assert :ok = Capabilities.validate_capability(:complete, capabilities)
      
      # Operation that requires multiple capabilities
      assert {:error, {:unsupported_operation, :stream_chat, missing}} = 
        Capabilities.validate_capability(:stream_chat, capabilities)
      assert :streaming in missing
    end
    
    test "validates with strict mode" do
      capabilities = [:chat]
      
      # Should fail in strict mode
      assert {:error, _} = Capabilities.validate_capability(:stream_chat, capabilities, strict: true)
      
      # Should be more lenient in non-strict mode
      assert :ok = Capabilities.validate_capability(:chat, capabilities, strict: false)
    end
  end
  
  describe "capability_metadata/2" do
    test "gets metadata for core capabilities" do
      {:ok, metadata} = Capabilities.capability_metadata(:chat)
      
      assert metadata.name == :chat
      assert metadata.level == :standard
      assert metadata.status == :available
      assert is_binary(metadata.description)
      assert is_list(metadata.dependencies)
    end
    
    test "gets interface-specific metadata" do
      {:ok, metadata} = Capabilities.capability_metadata(:completion, :lsp)
      
      assert metadata.name == :completion
      assert metadata.metadata.category == :lsp
    end
    
    test "handles unknown capabilities" do
      assert {:error, :capability_not_found} = 
        Capabilities.capability_metadata(:unknown_capability)
    end
  end
  
  describe "merge_capabilities/2" do
    test "merges capability sets with union strategy" do
      set1 = %{
        interface: :test1,
        capabilities: [
          %{name: :chat, level: :standard, status: :available},
          %{name: :complete, level: :standard, status: :available}
        ]
      }
      
      set2 = %{
        interface: :test2,
        capabilities: [
          %{name: :complete, level: :advanced, status: :available},
          %{name: :streaming, level: :advanced, status: :available}
        ]
      }
      
      {:ok, merged} = Capabilities.merge_capabilities([set1, set2], strategy: :union)
      
      capability_names = Enum.map(merged.capabilities, &Map.get(&1, :name))
      assert :chat in capability_names
      assert :complete in capability_names
      assert :streaming in capability_names
      
      # Should resolve conflicts (complete capability)
      complete_cap = Enum.find(merged.capabilities, &(Map.get(&1, :name) == :complete))
      assert complete_cap.level == :advanced  # Latest/highest level wins
    end
    
    test "merges with intersection strategy" do
      set1 = %{
        capabilities: [
          %{name: :chat, level: :standard},
          %{name: :complete, level: :standard}
        ]
      }
      
      set2 = %{
        capabilities: [
          %{name: :complete, level: :advanced},
          %{name: :streaming, level: :advanced}
        ]
      }
      
      {:ok, merged} = Capabilities.merge_capabilities([set1, set2], strategy: :intersection)
      
      capability_names = Enum.map(merged.capabilities, &Map.get(&1, :name))
      assert :complete in capability_names
      refute :chat in capability_names
      refute :streaming in capability_names
    end
    
    test "handles empty capability sets" do
      assert {:error, :no_capability_sets} = 
        Capabilities.merge_capabilities([], strategy: :intersection)
    end
  end
  
  describe "check_compatibility/3" do
    test "checks compatibility with interface expectations" do
      capability_set = %{
        capabilities: [
          %{name: :chat, level: :standard, status: :available},
          %{name: :complete, level: :standard, status: :available},
          %{name: :file_upload, level: :basic, status: :available}
        ]
      }
      
      {:ok, compatibility} = Capabilities.check_compatibility(capability_set, :cli)
      
      assert compatibility.coverage > 0.5
      assert is_list(compatibility.missing_capabilities)
      assert is_list(compatibility.extra_capabilities)
      assert compatibility.level in [:full, :high, :partial, :minimal]
    end
    
    test "detects incompatibility" do
      capability_set = %{
        capabilities: [
          %{name: :unknown_feature, level: :experimental, status: :experimental}
        ]
      }
      
      {:error, {:incompatible, reason}} = 
        Capabilities.check_compatibility(capability_set, :cli, strict: true)
      
      assert reason in [:missing_required_capabilities, :insufficient_capability_coverage]
    end
  end
  
  describe "get_interface_capabilities/1" do
    test "returns capabilities for each interface type" do
      cli_caps = Capabilities.get_interface_capabilities(:cli)
      web_caps = Capabilities.get_interface_capabilities(:web)
      lsp_caps = Capabilities.get_interface_capabilities(:lsp)
      
      assert is_list(cli_caps)
      assert is_list(web_caps)
      assert is_list(lsp_caps)
      
      # CLI should have interactive mode
      assert :interactive_mode in cli_caps
      
      # Web should have streaming
      assert :streaming in web_caps
      
      # LSP should have completion
      assert :completion in lsp_caps
      
      # All should have some common capabilities
      assert :chat in cli_caps
      assert :chat in web_caps
    end
    
    test "returns core capabilities for unknown interface" do
      unknown_caps = Capabilities.get_interface_capabilities(:unknown)
      
      assert is_list(unknown_caps)
      assert :chat in unknown_caps
      assert :complete in unknown_caps
    end
  end
  
  describe "validate_dependencies/2" do
    test "validates capability dependencies" do
      # session_management depends on authentication
      capabilities = [:authentication, :session_management]
      
      assert :ok = Capabilities.validate_dependencies(capabilities)
    end
    
    test "detects missing dependencies" do
      # session_management depends on authentication, but it's missing
      capabilities = [:session_management, :history]
      
      {:error, {:missing_dependencies, missing}} = 
        Capabilities.validate_dependencies(capabilities)
      
      assert :authentication in missing
    end
    
    test "handles capabilities with no dependencies" do
      capabilities = [:chat, :complete, :analyze]
      
      assert :ok = Capabilities.validate_dependencies(capabilities)
    end
    
    test "handles unknown capabilities gracefully" do
      capabilities = [:unknown_capability, :chat]
      
      # Should not fail, just ignore unknown capabilities
      assert :ok = Capabilities.validate_dependencies(capabilities)
    end
  end
  
  describe "capability levels and status" do
    test "categorizes capabilities by level" do
      {:ok, chat_meta} = Capabilities.capability_metadata(:chat)
      {:ok, analyze_meta} = Capabilities.capability_metadata(:analyze)
      {:ok, upload_meta} = Capabilities.capability_metadata(:file_upload)
      
      assert chat_meta.level == :standard
      assert analyze_meta.level == :advanced
      assert upload_meta.level == :basic
    end
    
    test "handles experimental capabilities" do
      {:ok, collab_meta} = Capabilities.capability_metadata(:real_time_collaboration, :web)
      
      assert collab_meta.status == :experimental
      assert collab_meta.level == :experimental
    end
  end
  
  describe "operation to capability mapping" do
    test "maps operations to required capabilities correctly" do
      # This tests the internal mapping function indirectly
      assert :ok = Capabilities.validate_capability(:chat, [:chat])
      assert :ok = Capabilities.validate_capability(:upload_file, [:file_upload])
      
      {:error, {:unsupported_operation, :stream_chat, missing}} = 
        Capabilities.validate_capability(:stream_chat, [:chat])
      assert :streaming in missing
    end
  end
end