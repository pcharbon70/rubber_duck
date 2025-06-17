defmodule RubberDuck.CodingAssistant.Engines.CodeAnalyserSecurityTest do
  use ExUnit.Case, async: true
  alias RubberDuck.CodingAssistant.Engines.CodeAnalyser

  describe "security vulnerability detection" do
    setup do
      config = %{languages: [:elixir, :javascript, :python], security_rules: :default}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end

    test "detects Code.eval_string vulnerabilities in Elixir", %{state: state} do
      vulnerable_code = %{
        file_path: "eval_vuln.ex",
        content: """
        defmodule Dangerous do
          def execute_user_code(user_input) do
            Code.eval_string(user_input)
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities,
            security_score: score
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      code_eval_vuln = Enum.find(vulnerabilities, &(&1.rule_id == :code_eval))
      assert code_eval_vuln != nil
      assert code_eval_vuln.severity == :high
      assert score < 100
    end

    test "detects eval vulnerabilities in JavaScript", %{state: state} do
      vulnerable_code = %{
        file_path: "eval_vuln.js",
        content: """
        function executeCode(userInput) {
          return eval(userInput);
        }
        """,
        language: :javascript
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      eval_vuln = Enum.find(vulnerabilities, &(&1.rule_id == :code_eval))
      assert eval_vuln != nil
    end

    test "detects SQL injection vulnerabilities", %{state: state} do
      vulnerable_code = %{
        file_path: "sql_vuln.ex",
        content: """
        defmodule UserService do
          def find_user(name) do
            query = "SELECT * FROM users WHERE name = '\#{name}'"
            Repo.query(query)
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      sql_vuln = Enum.find(vulnerabilities, &(&1.rule_id == :sql_injection))
      assert sql_vuln != nil
      assert sql_vuln.severity == :high
    end

    test "detects hardcoded secrets", %{state: state} do
      vulnerable_code = %{
        file_path: "secrets.ex",
        content: """
        defmodule Config do
          @api_key "sk-1234567890abcdef"
          @password "super_secret_password"
          @token "ghp_xxxxxxxxxxxxxxxxxxxx"
          
          def get_api_key, do: @api_key
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      secret_vulns = Enum.filter(vulnerabilities, &(&1.rule_id == :hardcoded_secret))
      assert length(secret_vulns) > 0
    end

    test "detects command injection vulnerabilities", %{state: state} do
      vulnerable_code = %{
        file_path: "command_injection.py",
        content: """
        import subprocess
        import os
        
        def process_file(filename):
            # Dangerous - user input directly in command
            os.system(f"cat {filename}")
            subprocess.call(f"rm {filename}", shell=True)
        """,
        language: :python
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      cmd_vulns = Enum.filter(vulnerabilities, &(&1.rule_id == :command_injection))
      assert length(cmd_vulns) > 0
    end

    test "detects path traversal vulnerabilities", %{state: state} do
      vulnerable_code = %{
        file_path: "path_traversal.js",
        content: """
        const fs = require('fs');
        const path = require('path');
        
        function readFile(filename) {
          // Dangerous - no path validation
          const filePath = './uploads/' + filename;
          return fs.readFileSync(filePath);
        }
        """,
        language: :javascript
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      path_vulns = Enum.filter(vulnerabilities, &(&1.rule_id == :path_traversal))
      assert length(path_vulns) > 0
    end

    test "detects insecure randomness", %{state: state} do
      vulnerable_code = %{
        file_path: "weak_random.ex",
        content: """
        defmodule TokenGenerator do
          def generate_session_token do
            :rand.uniform(1000000) |> to_string()
          end
          
          def generate_password_reset_token do
            Enum.random(1..999999)
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      random_vulns = Enum.filter(vulnerabilities, &(&1.rule_id == :weak_randomness))
      assert length(random_vulns) > 0
    end

    test "provides security recommendations", %{state: state} do
      vulnerable_code = %{
        file_path: "multiple_vulns.ex",
        content: """
        defmodule VulnerableCode do
          @api_key "secret_key_123"
          
          def dangerous_function(user_input) do
            Code.eval_string(user_input)
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(vulnerable_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities,
            recommendations: recommendations
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      assert length(recommendations) > 0
      assert is_list(recommendations)
      assert Enum.all?(recommendations, &is_binary/1)
    end

    test "calculates security score based on vulnerabilities", %{state: state} do
      safe_code = %{
        file_path: "safe.ex",
        content: """
        defmodule SafeCode do
          def add(a, b) do
            a + b
          end
        end
        """,
        language: :elixir
      }
      
      vulnerable_code = %{
        file_path: "vulnerable.ex", 
        content: """
        defmodule VulnerableCode do
          def eval_code(input), do: Code.eval_string(input)
        end
        """,
        language: :elixir
      }
      
      assert {:ok, safe_result, _} = CodeAnalyser.process_real_time(safe_code, state)
      assert {:ok, vuln_result, _} = CodeAnalyser.process_real_time(vulnerable_code, state)
      
      safe_score = safe_result.data.security.security_score
      vuln_score = vuln_result.data.security.security_score
      
      assert safe_score == 100
      assert vuln_score < safe_score
    end

    test "handles safe code without false positives", %{state: state} do
      safe_code = %{
        file_path: "safe_code.ex",
        content: """
        defmodule SafeCode do
          def process_data(data) do
            data
            |> Enum.map(&String.upcase/1)
            |> Enum.filter(&(&1 != ""))
          end
          
          def query_users(params) do
            User
            |> where(^params)
            |> Repo.all()
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(safe_code, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities,
            security_score: score
          }
        }
      } = result
      
      assert vulnerabilities == []
      assert score == 100
    end
  end

  describe "custom security rules" do
    test "supports custom security rules" do
      custom_rules = [
        %{
          id: :custom_vuln,
          pattern: ~r/dangerous_function/,
          severity: :medium,
          message: "Custom vulnerability detected"
        }
      ]
      
      config = %{languages: [:elixir], security_rules: custom_rules}
      {:ok, state} = CodeAnalyser.init(config)
      
      code_with_custom_vuln = %{
        file_path: "custom.ex",
        content: "def test, do: dangerous_function()",
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(code_with_custom_vuln, state)
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert length(vulnerabilities) > 0
      custom_vuln = Enum.find(vulnerabilities, &(&1.rule_id == :custom_vuln))
      assert custom_vuln != nil
      assert custom_vuln.severity == :medium
    end
  end
end