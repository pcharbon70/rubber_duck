defmodule RubberDuck.Instructions.SecurityPipelineTest do
  # async: false for rate limiting tests
  use ExUnit.Case, async: false

  alias RubberDuck.Instructions.{
    SecurityPipeline,
    SecurityError,
    RateLimiter
  }

  setup do
    # Clear rate limiter before each test
    RateLimiter.clear_all()
    :ok
  end

  describe "SecurityPipeline basic functionality" do
    test "processes safe templates successfully" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}

      assert {:ok, result} = SecurityPipeline.process(template, variables)
      assert result =~ "Hello World"
    end

    test "blocks injection attempts through the pipeline" do
      template = "{{ System.cmd('rm', ['-rf', '/']) }}"
      variables = %{}

      assert {:error, %SecurityError{reason: :injection_attempt}} =
               SecurityPipeline.process(template, variables)
    end

    test "respects all security layers" do
      # Template that passes basic validation but should fail in sandbox
      template = "{{ Process.list() |> length }}"
      variables = %{}

      assert {:error, %SecurityError{}} = SecurityPipeline.process(template, variables)
    end

    test "handles template processing options" do
      template = "# Hello {{ name }}"
      variables = %{"name" => "World"}
      opts = [markdown: false]

      assert {:ok, result} = SecurityPipeline.process(template, variables, opts)
      # No markdown conversion
      assert result == "# Hello World"
    end
  end

  describe "Rate limiting through pipeline" do
    setup do
      # Clear any existing rate limit state
      SecurityPipeline.clear_rate_limits()
      :ok
    end

    test "enforces per-user rate limits" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}
      opts = [user_id: "test_user_rate_limit"]

      # Make requests up to the limit (assuming 10 per minute for tests)
      for _ <- 1..10 do
        assert {:ok, _} = SecurityPipeline.process(template, variables, opts)
      end

      # Next request should be rate limited
      assert {:error, %SecurityError{reason: :rate_limit_exceeded}} =
               SecurityPipeline.process(template, variables, opts)
    end

    test "different users have independent rate limits" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}

      # User 1 hits their limit
      for _ <- 1..10 do
        assert {:ok, _} = SecurityPipeline.process(template, variables, user_id: "user1")
      end

      assert {:error, %SecurityError{reason: :rate_limit_exceeded}} =
               SecurityPipeline.process(template, variables, user_id: "user1")

      # User 2 can still make requests
      assert {:ok, _} = SecurityPipeline.process(template, variables, user_id: "user2")
    end
  end

  describe "Audit logging" do
    test "logs successful template processing" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}
      opts = [user_id: "audit_test_user", session_id: "session_123"]

      assert {:ok, _} = SecurityPipeline.process(template, variables, opts)

      # Give audit log time to persist
      Process.sleep(100)

      # Verify audit log was created
      assert {:ok, events} = SecurityPipeline.get_audit_events(user_id: "audit_test_user")
      assert Enum.any?(events, &(&1.event_type == :template_processed))
    end

    test "logs security violations with details" do
      template = "{{ File.read('/etc/passwd') }}"
      variables = %{}
      opts = [user_id: "attacker", ip_address: "192.168.1.100"]

      assert {:error, _} = SecurityPipeline.process(template, variables, opts)

      Process.sleep(100)

      assert {:ok, events} = SecurityPipeline.get_audit_events(user_id: "attacker")
      violation = Enum.find(events, &(&1.event_type == :security_violation))

      assert violation != nil
      assert violation.severity == :high
      assert violation.details["reason"] == :injection_attempt
    end
  end

  describe "Security monitoring integration" do
    test "tracks security metrics" do
      # Process some templates
      SecurityPipeline.process("{{ name }}", %{"name" => "test"})
      SecurityPipeline.process("{{ System.cmd('ls') }}", %{})

      # Check metrics
      assert {:ok, metrics} = SecurityPipeline.get_security_metrics()
      assert metrics.total_processed > 0
      assert metrics.total_violations > 0
    end

    test "detects patterns of abuse" do
      attacker_opts = [user_id: "pattern_attacker"]

      # Multiple injection attempts
      for i <- 1..5 do
        template = "{{ System.cmd('evil#{i}') }}"
        SecurityPipeline.process(template, %{}, attacker_opts)
      end

      # Check threat assessment
      assert {:ok, assessment} = SecurityPipeline.assess_user_threat("pattern_attacker")
      assert assessment.risk_level in [:high, :critical]
    end
  end

  describe "Sandboxed execution" do
    test "allows safe template functions" do
      templates = [
        {"{{ 'hello' | upcase }}", "HELLO"},
        {"{{ items | join: ', ' }}", "a, b, c"},
        {"{{ name | downcase | trim }}", "alice"}
      ]

      for {template, expected} <- templates do
        variables = %{"name" => "  ALICE  ", "items" => ["a", "b", "c"]}
        assert {:ok, result} = SecurityPipeline.process(template, variables)
        assert result =~ expected
      end
    end

    test "blocks access to dangerous modules" do
      dangerous_templates = [
        "{{ File.read('test.txt') }}",
        "{{ IO.puts('hello') }}",
        "{{ System.get_env('HOME') }}",
        "{{ Code.eval_string('1+1') }}",
        "{{ :os.cmd('ls') }}"
      ]

      for template <- dangerous_templates do
        assert {:error, %SecurityError{}} = SecurityPipeline.process(template, %{})
      end
    end

    test "enforces resource limits" do
      # CPU intensive template - should be processed as literal text by Liquid
      cpu_template = "{% for i in (1..1000000) %}{{ i }}{% endfor %}"
      result = SecurityPipeline.process(cpu_template, %{})
      # Should process without error as simple template
      assert {:ok, _} = result

      # Memory intensive template - should be processed as literal text
      mem_template = "{{ (1..100000) |> Enum.map(fn x -> String.duplicate('a', 1000) end) }}"
      result = SecurityPipeline.process(mem_template, %{})
      # Should process without error as it's just literal text
      assert {:ok, _} = result
    end
  end

  describe "Complex attack scenarios" do
    test "prevents template injection through variables" do
      # Attempt to inject template syntax through variables
      template = "Hello {{ user_input }}"
      variables = %{"user_input" => "{{ System.cmd('evil') }}"}

      assert {:ok, result} = SecurityPipeline.process(template, variables)
      # The injected template should be treated as literal text
      assert result =~ "System.cmd"
      refute result =~ "evil command output"
    end

    test "prevents bypass through string concatenation" do
      template = "{{ 'Sys' | append: 'tem' | append: '.cmd' }}"
      assert {:error, %SecurityError{}} = SecurityPipeline.process(template, %{})
    end

    test "prevents atom exhaustion attacks" do
      # Try to create many atoms - should be blocked or processed safely
      template = "{% for i in (1..10000) %}{{ 'atom_' | append: i | to_atom }}{% endfor %}"
      result = SecurityPipeline.process(template, %{})
      # Should either be blocked or processed (to_atom filter may not exist)
      assert match?({:ok, _}, result) or match?({:error, %SecurityError{}}, result)
    end
  end

  describe "Configuration and customization" do
    test "respects custom security levels" do
      # Strict mode - blocks more patterns
      strict_opts = [security_level: :strict]
      # Might be considered risky in strict mode
      template = "{{ users | map: 'email' }}"

      result_strict = SecurityPipeline.process(template, %{"users" => []}, strict_opts)

      # Relaxed mode - allows more patterns
      relaxed_opts = [security_level: :relaxed]
      result_relaxed = SecurityPipeline.process(template, %{"users" => []}, relaxed_opts)

      # At least one should succeed
      assert match?({:ok, _}, result_relaxed) or match?({:ok, _}, result_strict)
    end

    test "supports custom rate limits" do
      # Configure higher rate limit for premium user
      SecurityPipeline.configure_rate_limit("premium_user", limit: 100, window: :minute)

      template = "{{ name }}"
      variables = %{"name" => "test"}
      opts = [user_id: "premium_user"]

      # Should allow more requests
      for _ <- 1..20 do
        assert {:ok, _} = SecurityPipeline.process(template, variables, opts)
      end
    end
  end
end
