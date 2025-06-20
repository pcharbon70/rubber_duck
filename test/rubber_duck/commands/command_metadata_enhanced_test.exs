defmodule RubberDuck.Commands.CommandMetadataEnhancedTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Commands.CommandMetadata
  alias RubberDuck.Commands.CommandMetadata.Parameter

  describe "Enhanced parameter types" do
    test "supports file_path parameter type" do
      param = %Parameter{
        name: :file,
        type: :file_path,
        required: true,
        description: "Path to file"
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, "/path/to/file.txt")
      assert {:error, _} = Parameter.validate_value(param, "/invalid<path")
    end

    test "supports enum parameter type with choices" do
      param = %Parameter{
        name: :format,
        type: :enum,
        required: true,
        description: "Output format",
        choices: ["json", "xml", "yaml"]
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, "json")
      assert {:error, _} = Parameter.validate_value(param, "csv")
    end

    test "supports regex parameter type" do
      param = %Parameter{
        name: :pattern,
        type: :regex,
        required: true,
        description: "Regex pattern"
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, "\\d+")
      assert {:error, _} = Parameter.validate_value(param, "[invalid")
    end

    test "supports url parameter type" do
      param = %Parameter{
        name: :endpoint,
        type: :url,
        required: true,
        description: "API endpoint"
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, "https://api.example.com")
      assert {:error, _} = Parameter.validate_value(param, "not-a-url")
    end

    test "supports json parameter type" do
      param = %Parameter{
        name: :config,
        type: :json,
        required: true,
        description: "JSON configuration"
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, "{\"key\": \"value\"}")
      assert {:error, _} = Parameter.validate_value(param, "{invalid json")
    end
  end

  describe "Parameter validation enhancements" do
    test "validates min/max values for numeric parameters" do
      param = %Parameter{
        name: :count,
        type: :integer,
        required: true,
        description: "Count value",
        min_value: 1,
        max_value: 100
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, 50)
      assert {:error, _} = Parameter.validate_value(param, 0)
      assert {:error, _} = Parameter.validate_value(param, 101)
    end

    test "validates pattern for string parameters" do
      param = %Parameter{
        name: :email,
        type: :string,
        required: true,
        description: "Email address",
        pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, "test@example.com")
      assert {:error, _} = Parameter.validate_value(param, "invalid-email")
    end

    test "supports multiple values" do
      param = %Parameter{
        name: :files,
        type: :string_list,
        required: true,
        description: "List of files",
        multiple: true
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, ["file1.txt", "file2.txt"])
      assert {:error, _} = Parameter.validate_value(param, ["file1.txt", 123])
    end

    test "supports custom validator function" do
      param = %Parameter{
        name: :port,
        type: :integer,
        required: true,
        description: "Port number",
        validator: fn port -> port > 1024 and port < 65536 end
      }

      assert %Parameter{} = Parameter.validate!(param)
      assert :ok = Parameter.validate_value(param, 8080)
      assert {:error, _} = Parameter.validate_value(param, 80)
    end
  end

  describe "Parameter dependencies" do
    test "supports parameter dependencies" do
      param = %Parameter{
        name: :ssl_cert,
        type: :file_path,
        required: false,
        description: "SSL certificate file",
        depends_on: [
          %{parameter: :ssl_enabled, condition: :equals, value: true}
        ]
      }

      assert %Parameter{} = Parameter.validate!(param)
    end

    test "validates dependency references" do
      metadata = %CommandMetadata{
        name: "test_cmd",
        description: "Test command",
        category: :testing,
        parameters: [
          %Parameter{
            name: :ssl_enabled,
            type: :boolean,
            required: false,
            description: "Enable SSL"
          },
          %Parameter{
            name: :ssl_cert,
            type: :file_path,
            required: false,
            description: "SSL certificate",
            depends_on: [
              %{parameter: :ssl_enabled, condition: :equals, value: true}
            ]
          }
        ]
      }

      assert %CommandMetadata{} = CommandMetadata.validate!(metadata)
    end

    test "raises error for invalid dependency references" do
      assert_raise ArgumentError, ~r/depends on non-existent parameter/, fn ->
        %CommandMetadata{
          name: "test_cmd",
          description: "Test command",
          category: :testing,
          parameters: [
            %Parameter{
              name: :ssl_cert,
              type: :file_path,
              required: false,
              description: "SSL certificate",
              depends_on: [
                %{parameter: :non_existent, condition: :equals, value: true}
              ]
            }
          ]
        } |> CommandMetadata.validate!()
      end
    end
  end

  describe "Conditional parameter visibility" do
    test "shows parameter when condition is met" do
      param = %Parameter{
        name: :ssl_cert,
        type: :file_path,
        required: false,
        description: "SSL certificate",
        conditional_visibility: %{
          show_when: [
            %{parameter: :ssl_enabled, condition: :equals, value: true}
          ]
        }
      }

      assert CommandMetadata.is_parameter_visible?(param, %{ssl_enabled: true})
      refute CommandMetadata.is_parameter_visible?(param, %{ssl_enabled: false})
    end

    test "hides parameter when hide condition is met" do
      param = %Parameter{
        name: :debug_logs,
        type: :boolean,
        required: false,
        description: "Enable debug logging",
        conditional_visibility: %{
          hide_when: [
            %{parameter: :production, condition: :equals, value: true}
          ]
        }
      }

      refute CommandMetadata.is_parameter_visible?(param, %{production: true})
      assert CommandMetadata.is_parameter_visible?(param, %{production: false})
    end
  end

  describe "Parameter groups" do
    test "creates parameter groups" do
      metadata = %CommandMetadata{
        name: "complex_cmd",
        description: "Complex command",
        category: :testing,
        parameters: [
          %Parameter{name: :input, type: :string, required: true, description: "Input", group: "basic"},
          %Parameter{name: :output, type: :string, required: false, description: "Output", group: "basic"},
          %Parameter{name: :verbose, type: :boolean, required: false, description: "Verbose", group: "advanced"}
        ],
        parameter_groups: [
          %{name: "basic", description: "Basic options", parameters: [:input, :output], collapsible: false, advanced: false},
          %{name: "advanced", description: "Advanced options", parameters: [:verbose], collapsible: true, advanced: true}
        ]
      }

      assert %CommandMetadata{} = CommandMetadata.validate!(metadata)
      
      groups = CommandMetadata.parameters_by_group(metadata)
      assert Map.has_key?(groups, "basic")
      assert Map.has_key?(groups, "advanced")
      assert length(groups["basic"]) == 2
      assert length(groups["advanced"]) == 1
    end

    test "validates parameter group references" do
      assert_raise ArgumentError, ~r/references non-existent parameters/, fn ->
        %CommandMetadata{
          name: "test_cmd",
          description: "Test command",
          category: :testing,
          parameters: [
            %Parameter{name: :input, type: :string, required: true, description: "Input"}
          ],
          parameter_groups: [
            %{name: "basic", description: "Basic", parameters: [:input, :non_existent], collapsible: false, advanced: false}
          ]
        } |> CommandMetadata.validate!()
      end
    end
  end

  describe "When conditions" do
    test "supports file type conditions" do
      metadata = %CommandMetadata{
        name: "lint_js",
        description: "Lint JavaScript",
        category: :analysis,
        when_conditions: [
          %{type: :file_type, condition: ["js", "ts"], description: "JavaScript/TypeScript files"}
        ]
      }

      assert %CommandMetadata{} = CommandMetadata.validate!(metadata)
      assert CommandMetadata.is_available?(metadata, %{file_path: "test.js"})
      refute CommandMetadata.is_available?(metadata, %{file_path: "test.py"})
    end

    test "supports project type conditions" do
      metadata = %CommandMetadata{
        name: "mix_deps",
        description: "Mix dependencies",
        category: :elixir,
        when_conditions: [
          %{type: :project_type, condition: :elixir, description: "Elixir projects"}
        ]
      }

      assert %CommandMetadata{} = CommandMetadata.validate!(metadata)
      assert CommandMetadata.is_available?(metadata, %{project_type: :elixir})
      refute CommandMetadata.is_available?(metadata, %{project_type: :node})
    end

    test "supports interface conditions" do
      metadata = %CommandMetadata{
        name: "interactive_setup",
        description: "Interactive setup",
        category: :setup,
        when_conditions: [
          %{type: :interface, condition: :tui, description: "TUI interface"}
        ]
      }

      assert %CommandMetadata{} = CommandMetadata.validate!(metadata)
      assert CommandMetadata.is_available?(metadata, %{interface: :tui})
      refute CommandMetadata.is_available?(metadata, %{interface: :cli})
    end
  end

  describe "Pipeline support" do
    test "detects pipeline support" do
      metadata = %CommandMetadata{
        name: "process_data",
        description: "Process data",
        category: :data,
        input_types: [:json],
        output_types: [:csv]
      }

      assert CommandMetadata.supports_pipeline?(metadata)
    end

    test "checks command chaining compatibility" do
      cmd1 = %CommandMetadata{
        name: "parse_json",
        description: "Parse JSON",
        category: :data,
        output_types: [:structured_data]
      }

      cmd2 = %CommandMetadata{
        name: "format_csv",
        description: "Format as CSV",
        category: :data,
        input_types: [:structured_data],
        output_types: [:csv]
      }

      assert CommandMetadata.can_chain_after?(cmd2, cmd1)
      refute CommandMetadata.can_chain_after?(cmd1, cmd2)
    end
  end

  describe "Enhanced help generation" do
    test "generates help with parameter groups" do
      metadata = %CommandMetadata{
        name: "enhanced_cmd",
        description: "Enhanced command with groups",
        category: :testing,
        version: "2.0.0",
        tags: [:experimental, :beta],
        parameters: [
          %Parameter{
            name: :input,
            type: :file_path,
            required: true,
            description: "Input file",
            group: "basic",
            placeholder: "/path/to/file.txt"
          },
          %Parameter{
            name: :verbose,
            type: :boolean,
            required: false,
            description: "Enable verbose output",
            group: "advanced",
            default: false
          }
        ]
      }

      help = CommandMetadata.help_text(metadata)
      assert String.contains?(help, "enhanced_cmd - Enhanced command with groups")
      assert String.contains?(help, "Version: 2.0.0")
      assert String.contains?(help, "Tags: experimental, beta")
      assert String.contains?(help, "basic:")
      assert String.contains?(help, "advanced:")
      assert String.contains?(help, "Placeholder: /path/to/file.txt")
    end

    test "generates interface-specific help" do
      metadata = %CommandMetadata{
        name: "interface_cmd",
        description: "Interface-aware command",
        category: :testing,
        parameters: [
          %Parameter{
            name: :file,
            type: :file_path,
            required: true,
            description: "Select file",
            interface_hints: %{
              cli: %{input_type: :text},
              tui: %{input_type: :file_picker, hidden: false}
            }
          }
        ]
      }

      cli_help = CommandMetadata.help_text_for_interface(metadata, :cli)
      tui_help = CommandMetadata.help_text_for_interface(metadata, :tui)

      assert String.contains?(tui_help, "Interface: File picker")
      refute String.contains?(cli_help, "Interface: File picker")
    end
  end

  describe "Category hierarchy" do
    test "parses hierarchical categories" do
      metadata = %CommandMetadata{
        name: "security_scan",
        description: "Security scanner",
        category: :"analysis.security.vulnerability"
      }

      hierarchy = CommandMetadata.category_hierarchy(metadata)
      assert hierarchy == [:analysis, :security, :vulnerability]
    end
  end

  describe "Parameter value validation" do
    test "validates all parameters with visible parameter filtering" do
      metadata = %CommandMetadata{
        name: "conditional_cmd",
        description: "Command with conditional parameters",
        category: :testing,
        parameters: [
          %Parameter{
            name: :mode,
            type: :enum,
            required: true,
            description: "Operation mode",
            choices: ["simple", "advanced"]
          },
          %Parameter{
            name: :config_file,
            type: :file_path,
            required: true,
            description: "Configuration file",
            conditional_visibility: %{
              show_when: [
                %{parameter: :mode, condition: :equals, value: "advanced"}
              ]
            }
          }
        ]
      }

      # Simple mode - config_file should not be required
      assert :ok = CommandMetadata.validate_parameters(metadata, %{mode: "simple"})
      
      # Advanced mode - config_file should be required
      assert {:error, errors} = CommandMetadata.validate_parameters(metadata, %{mode: "advanced"})
      assert Keyword.has_key?(errors, :config_file)
      
      # Advanced mode with config_file - should be valid
      assert :ok = CommandMetadata.validate_parameters(metadata, %{mode: "advanced", config_file: "/path/to/config.json"})
    end
  end
end