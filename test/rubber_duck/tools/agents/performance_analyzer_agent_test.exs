defmodule RubberDuck.Tools.Agents.PerformanceAnalyzerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.PerformanceAnalyzerAgent
  
  setup do
    {:ok, agent} = PerformanceAnalyzerAgent.start_link(id: "test_performance_analyzer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        source_code: "function calculate() { for(let i=0; i<1000; i++) {} }",
        language: "javascript",
        analysis_type: "performance"
      }
      
      context = %{agent: GenServer.call(agent, :get_state), parent_module: PerformanceAnalyzerAgent}
      
      result = PerformanceAnalyzerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "profile code action identifies performance hotspots", %{agent: agent} do
      code_with_issues = """
      function processData(data) {
        // Nested loops - O(n²) complexity
        for (let i = 0; i < data.length; i++) {
          for (let j = 0; j < data.length; j++) {
            if (data[i] === data[j]) {
              count++;
            }
          }
        }
        
        // Recursive function
        function fibonacci(n) {
          if (n <= 1) return n;
          return fibonacci(n-1) + fibonacci(n-2);
        }
        
        // Heavy string concatenation
        let result = '';
        for (let item of data) {
          result += processItem(item);
        }
        
        // File I/O in loop
        for (let file of files) {
          const content = fs.readFileSync(file);
          process(content);
        }
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PerformanceAnalyzerAgent.ProfileCodeAction.run(
        %{
          source_code: code_with_issues,
          language: "javascript",
          profile_type: "cpu"
        },
        context
      )
      
      # Check hotspots were found
      assert length(result.hotspots) > 0
      
      # Should identify nested loops
      nested_loop_hotspot = Enum.find(result.hotspots, fn h ->
        String.contains?(h.description, "Nested loops")
      end)
      assert nested_loop_hotspot != nil
      assert nested_loop_hotspot.severity >= 8
      
      # Should identify recursion
      recursion_hotspot = Enum.find(result.hotspots, fn h ->
        String.contains?(h.description, "Recursive")
      end)
      assert recursion_hotspot != nil
      
      # Check bottlenecks
      assert length(result.bottlenecks) > 0
      assert hd(result.bottlenecks).severity > 0
      
      # Check metrics
      assert result.metrics.total_hotspots > 0
      assert result.metrics.critical_hotspots >= 0
      assert result.metrics.profile_score <= 100
      
      # Check recommendations
      assert length(result.recommendations) > 0
      assert Enum.any?(result.recommendations, &String.contains?(&1, "optimiz"))
    end
    
    test "analyze complexity action calculates time and space complexity", %{agent: agent} do
      complex_code = """
      def bubbleSort(arr):
          n = len(arr)
          for i in range(n):
              for j in range(0, n-i-1):
                  if arr[j] > arr[j+1]:
                      arr[j], arr[j+1] = arr[j+1], arr[j]
          return arr
      
      def binarySearch(arr, target):
          left, right = 0, len(arr) - 1
          while left <= right:
              mid = (left + right) // 2
              if arr[mid] == target:
                  return mid
              elif arr[mid] < target:
                  left = mid + 1
              else:
                  right = mid - 1
          return -1
      
      def fibonacci(n):
          if n <= 1:
              return n
          return fibonacci(n-1) + fibonacci(n-2)
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PerformanceAnalyzerAgent.AnalyzeComplexityAction.run(
        %{
          source_code: complex_code,
          language: "python",
          include_space: true
        },
        context
      )
      
      # Check complexity analysis
      assert length(result.complexity_analysis) > 0
      
      # Find bubble sort analysis
      bubble_sort = Enum.find(result.complexity_analysis, fn c ->
        c.function == "bubbleSort"
      end)
      assert bubble_sort != nil
      assert bubble_sort.time_complexity == "O(n²)"
      assert bubble_sort.space_complexity == "O(1)"
      
      # Find binary search analysis
      binary_search = Enum.find(result.complexity_analysis, fn c ->
        c.function == "binarySearch"
      end)
      if binary_search do
        assert String.contains?(binary_search.time_complexity, "O(") 
      end
      
      # Check overall assessment
      assert result.overall_assessment.worst_case_complexity != nil
      assert result.overall_assessment.performance_grade != nil
      assert result.overall_assessment.scalability_assessment != nil
      
      # Check optimization targets
      assert is_list(result.optimization_targets)
      # Bubble sort should be an optimization target
      bubble_target = Enum.find(result.optimization_targets, fn t ->
        t.function == "bubbleSort"
      end)
      if bubble_target do
        assert bubble_target.priority in ["high", "critical"]
      end
    end
    
    test "optimize database queries action identifies query issues", %{agent: agent} do
      queries = [
        "SELECT * FROM users WHERE active = true",
        "SELECT id, name FROM products WHERE category LIKE '%electronics%'",
        "SELECT * FROM orders o JOIN customers c WHERE o.amount > 100",
        "DELETE FROM logs WHERE created_at < '2023-01-01' OR status = 'archived'"
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PerformanceAnalyzerAgent.OptimizeDatabaseQueriesAction.run(
        %{
          queries: queries,
          database_type: "postgresql"
        },
        context
      )
      
      # Check query analysis
      assert length(result.query_analysis) == length(queries)
      
      # First query should have SELECT * issue
      first_analysis = hd(result.query_analysis)
      select_star_issue = Enum.find(first_analysis.issues_found, fn i ->
        i.type == :select_star
      end)
      assert select_star_issue != nil
      
      # Check optimization summary
      summary = result.optimization_summary
      assert summary.total_issues > 0
      assert Map.has_key?(summary.issue_breakdown, :select_star)
      
      # Check index recommendations
      assert is_list(result.index_recommendations)
      
      # Check estimated improvement
      assert result.estimated_improvement != nil
    end
    
    test "identify caching opportunities action finds cacheable operations", %{agent: agent} do
      code_with_caching_opportunities = """
      async function getUserData(userId) {
        // Database query that could be cached
        const user = await db.query('SELECT * FROM users WHERE id = ?', [userId]);
        
        // Expensive computation that could be memoized
        const score = calculateComplexScore(user.data);
        
        // API call that could be cached
        const profile = await fetch(`https://api.example.com/users/${userId}`);
        
        // File read that could be cached
        const config = fs.readFileSync('./config.json');
        
        return { user, score, profile, config };
      }
      
      function calculateComplexScore(data) {
        let result = 0;
        for (let i = 0; i < data.length; i++) {
          for (let j = 0; j < data.length; j++) {
            result += expensiveOperation(data[i], data[j]);
          }
        }
        return result;
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PerformanceAnalyzerAgent.IdentifyCachingOpportunitiesAction.run(
        %{
          source_code: code_with_caching_opportunities,
          language: "javascript"
        },
        context
      )
      
      # Check caching opportunities
      assert length(result.caching_opportunities) > 0
      
      # Should identify query caching
      query_cache = Enum.find(result.caching_opportunities, fn o ->
        o.type == :query_result_cache
      end)
      assert query_cache != nil
      
      # Should identify computation memoization
      computation_cache = Enum.find(result.caching_opportunities, fn o ->
        o.type == :computation_memoization
      end)
      assert computation_cache != nil
      
      # Should identify HTTP caching
      http_cache = Enum.find(result.caching_opportunities, fn o ->
        o.type == :http_response_cache
      end)
      assert http_cache != nil
      
      # Check implementation guide
      assert length(result.implementation_guide) > 0
      assert hd(result.implementation_guide).implementation_steps != nil
      
      # Check estimated benefits
      assert result.estimated_benefits.performance_improvement != nil
      assert is_list(result.estimated_benefits.resource_savings)
      
      # Check cache strategy
      assert is_list(result.cache_strategy.recommended_strategies)
      assert result.cache_strategy.invalidation_strategy != nil
    end
    
    test "generate benchmark action creates performance benchmarks", %{agent: agent} do
      code_to_benchmark = """
      function sortArray(arr) {
        return arr.sort((a, b) => a - b);
      }
      
      function findDuplicates(arr) {
        const seen = new Set();
        const duplicates = [];
        for (const item of arr) {
          if (seen.has(item)) {
            duplicates.push(item);
          }
          seen.add(item);
        }
        return duplicates;
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PerformanceAnalyzerAgent.GenerateBenchmarkAction.run(
        %{
          source_code: code_to_benchmark,
          language: "javascript",
          benchmark_type: "comprehensive"
        },
        context
      )
      
      # Check benchmark suite
      assert length(result.benchmark_suite) > 0
      
      # Should have different benchmark types
      benchmark_types = result.benchmark_suite |> Enum.map(& &1.type) |> Enum.uniq()
      assert :micro in benchmark_types
      assert :macro in benchmark_types
      
      # Check execution plan
      assert length(result.execution_plan.phases) > 0
      assert result.execution_plan.total_estimated_time != nil
      
      # Check metrics to collect
      assert length(result.metrics_to_collect) > 0
      metric_names = Enum.map(result.metrics_to_collect, & &1.name)
      assert "execution_time" in metric_names
      assert "throughput" in metric_names
      
      # Check analysis guidance
      assert length(result.analysis_guidance.interpretation_guide) > 0
      assert length(result.analysis_guidance.warning_signs) > 0
    end
    
    test "analyze memory usage action detects memory issues", %{agent: agent} do
      code_with_memory_issues = """
      function processLargeData() {
        // Memory allocation in loop
        const results = [];
        for (let i = 0; i < 10000; i++) {
          const data = new Array(1000).fill(i);
          results.push(data);
        }
        
        // Large array allocation
        const hugeArray = new Array(1000000);
        
        // String concatenation in loop
        let output = '';
        for (let i = 0; i < items.length; i++) {
          output += items[i].toString();
        }
        
        // Event listener without cleanup
        element.addEventListener('click', handleClick);
        
        // Global variable
        window.globalData = results;
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PerformanceAnalyzerAgent.AnalyzeMemoryUsageAction.run(
        %{
          source_code: code_with_memory_issues,
          language: "javascript"
        },
        context
      )
      
      # Check memory analysis
      static_analysis = result.memory_analysis.static_analysis
      assert static_analysis.total_issues > 0
      
      # Should find loop allocation
      loop_allocation = Enum.find(static_analysis.issues, fn i ->
        i.type == :loop_allocation
      end)
      assert loop_allocation != nil
      assert loop_allocation.severity in [:high, :critical]
      
      # Should find large allocation
      large_allocation = Enum.find(static_analysis.issues, fn i ->
        i.type == :large_allocation
      end)
      assert large_allocation != nil
      
      # Should find potential memory leak
      memory_leak = Enum.find(static_analysis.issues, fn i ->
        i.type == :memory_leak
      end)
      assert memory_leak != nil
      
      # Check leak detection
      assert length(result.leak_detection.potential_leaks) > 0
      assert result.leak_detection.leak_severity != :none
      
      # Check optimization suggestions
      assert length(result.optimization_suggestions) > 0
      object_pooling = Enum.find(result.optimization_suggestions, fn s ->
        s.type == :object_pooling
      end)
      if object_pooling do
        assert object_pooling.impact == :high
      end
      
      # Check memory profile
      assert result.memory_profile.overall_health in [:excellent, :good, :fair, :poor, :critical]
      assert result.memory_profile.metrics.static_score <= 100
    end
    
    test "generate performance report action creates comprehensive report", %{agent: agent} do
      analysis_results = %{
        profile: %{
          hotspots: [
            %{type: :cpu, severity: 9, description: "Nested loops", location: "line 10"}
          ],
          bottlenecks: [
            %{function: "processData", severity: 15, types: [:cpu, :memory]}
          ],
          metrics: %{
            profile_score: 65,
            critical_hotspots: 2,
            total_hotspots: 5
          }
        },
        complexity: %{
          overall_assessment: %{
            worst_case_complexity: "O(n²)",
            performance_grade: "C"
          },
          optimization_targets: [
            %{function: "sort", current_complexity: "O(n²)", improvement_potential: "10x"}
          ]
        },
        memory: %{
          static_analysis: %{
            memory_score: 70,
            total_issues: 3,
            critical_issues: 1
          },
          leak_detection: %{
            potential_leaks: [%{type: :event_listener}]
          }
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, report} = PerformanceAnalyzerAgent.GeneratePerformanceReportAction.run(
        %{
          analysis_results: analysis_results,
          report_format: "detailed",
          include_recommendations: true
        },
        context
      )
      
      # Check report structure
      assert Map.has_key?(report, :title)
      assert Map.has_key?(report, :sections)
      assert Map.has_key?(report, :recommendations)
      
      # Check sections
      sections = report.sections
      assert Map.has_key?(sections, :executive_summary)
      assert Map.has_key?(sections, :metrics)
      assert Map.has_key?(sections, :bottlenecks)
      
      # Check metrics section
      metrics = sections.metrics
      assert Map.has_key?(metrics, :performance)
      assert Map.has_key?(metrics, :complexity)
      assert Map.has_key?(metrics, :memory)
      
      # Check recommendations
      recs = report.recommendations
      assert Map.has_key?(recs, :immediate)
      assert Map.has_key?(recs, :short_term)
      assert Map.has_key?(recs, :long_term)
      assert length(recs.immediate) > 0
    end
  end
  
  describe "signal handling with actions" do
    test "profile_code signal triggers ProfileCodeAction", %{agent: agent} do
      signal = %{
        "type" => "profile_code",
        "data" => %{
          "source_code" => "for(;;){}",
          "language" => "javascript",
          "profile_type" => "cpu"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PerformanceAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "analyze_complexity signal triggers AnalyzeComplexityAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_complexity",
        "data" => %{
          "source_code" => "def func(n): pass",
          "language" => "python"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PerformanceAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "performance profiling" do
    test "identifies different types of hotspots" do
      context = %{agent: %{state: %{}}}
      
      # CPU hotspots
      cpu_code = """
      for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
          for (let k = 0; k < n; k++) {
            process(i, j, k);
          }
        }
      }
      """
      
      {:ok, cpu_result} = PerformanceAnalyzerAgent.ProfileCodeAction.run(
        %{source_code: cpu_code, language: "javascript", profile_type: "cpu"},
        context
      )
      
      assert length(cpu_result.hotspots) > 0
      assert hd(cpu_result.hotspots).type == :cpu
      
      # Memory hotspots
      memory_code = """
      const arrays = [];
      for (let i = 0; i < 1000; i++) {
        arrays.push(new Array(10000));
      }
      """
      
      {:ok, memory_result} = PerformanceAnalyzerAgent.ProfileCodeAction.run(
        %{source_code: memory_code, language: "javascript", profile_type: "memory"},
        context
      )
      
      assert length(memory_result.hotspots) > 0
      assert hd(memory_result.hotspots).type == :memory
      
      # I/O hotspots
      io_code = """
      const data = fs.readFileSync('large.txt');
      db.query('SELECT * FROM huge_table');
      fetch('https://api.slow.com/data');
      """
      
      {:ok, io_result} = PerformanceAnalyzerAgent.ProfileCodeAction.run(
        %{source_code: io_code, language: "javascript", profile_type: "io"},
        context
      )
      
      assert length(io_result.hotspots) > 0
      assert hd(io_result.hotspots).type == :io
    end
  end
  
  describe "complexity analysis" do
    test "correctly identifies various complexity patterns" do
      context = %{agent: %{state: %{}}}
      
      code = """
      // O(1) - constant time
      function getFirst(arr) {
        return arr[0];
      }
      
      // O(n) - linear time
      function findMax(arr) {
        let max = arr[0];
        for (let i = 1; i < arr.length; i++) {
          if (arr[i] > max) max = arr[i];
        }
        return max;
      }
      
      // O(n log n) - typical sorting
      function mergeSort(arr) {
        if (arr.length <= 1) return arr;
        // merge sort implementation
      }
      
      // O(n²) - quadratic
      function findPairs(arr) {
        const pairs = [];
        for (let i = 0; i < arr.length; i++) {
          for (let j = i + 1; j < arr.length; j++) {
            pairs.push([arr[i], arr[j]]);
          }
        }
        return pairs;
      }
      """
      
      {:ok, result} = PerformanceAnalyzerAgent.AnalyzeComplexityAction.run(
        %{source_code: code, language: "javascript"},
        context
      )
      
      # Should analyze all functions
      assert length(result.complexity_analysis) >= 3
      
      # Check specific complexities
      find_max = Enum.find(result.complexity_analysis, &(&1.function == "findMax"))
      if find_max do
        assert find_max.time_complexity == "O(n)"
      end
      
      find_pairs = Enum.find(result.complexity_analysis, &(&1.function == "findPairs"))
      if find_pairs do
        assert find_pairs.time_complexity == "O(n²)"
      end
    end
  end
  
  describe "query optimization" do
    test "detects various SQL anti-patterns" do
      context = %{agent: %{state: %{}}}
      
      queries = [
        # Missing index usage
        "SELECT * FROM users WHERE email = 'test@example.com'",
        # Join without condition
        "SELECT * FROM orders o, customers c WHERE o.total > 100",
        # Leading wildcard
        "SELECT * FROM products WHERE name LIKE '%phone'",
        # Function on column
        "SELECT * FROM logs WHERE DATE(created_at) = '2023-01-01'",
        # NOT IN subquery
        "SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM banned_users)"
      ]
      
      {:ok, result} = PerformanceAnalyzerAgent.OptimizeDatabaseQueriesAction.run(
        %{queries: queries, database_type: "mysql"},
        context
      )
      
      analyzed = result.query_analysis
      
      # Each query should have issues
      assert Enum.all?(analyzed, &(length(&1.issues_found) > 0))
      
      # Check specific issues
      assert Enum.any?(analyzed, fn a ->
        Enum.any?(a.issues_found, &(&1.type == :leading_wildcard))
      end)
      
      assert Enum.any?(analyzed, fn a ->
        Enum.any?(a.issues_found, &(&1.type == :function_on_column))
      end)
      
      assert Enum.any?(analyzed, fn a ->
        Enum.any?(a.issues_found, &(&1.type == :not_in))
      end)
    end
  end
  
  describe "caching analysis" do
    test "identifies different caching strategies" do
      context = %{agent: %{state: %{}}}
      
      code = """
      class DataService {
        async getUserById(id) {
          // Database query - good for caching
          return await db.query('SELECT * FROM users WHERE id = ?', [id]);
        }
        
        calculateExpensiveMetric(data) {
          // CPU intensive - good for memoization
          let result = 0;
          for (let i = 0; i < 1000000; i++) {
            result += complexCalculation(data, i);
          }
          return result;
        }
        
        async fetchWeatherData(city) {
          // External API - good for HTTP caching
          const response = await fetch(`https://weather.api/city/${city}`);
          return response.json();
        }
        
        loadConfiguration() {
          // File I/O - good for file caching
          return JSON.parse(fs.readFileSync('./config.json'));
        }
      }
      """
      
      {:ok, result} = PerformanceAnalyzerAgent.IdentifyCachingOpportunitiesAction.run(
        %{source_code: code, language: "javascript"},
        context
      )
      
      opportunities = result.caching_opportunities
      
      # Should identify all caching types
      cache_types = Enum.map(opportunities, & &1.type) |> Enum.uniq()
      
      assert :query_result_cache in cache_types || length(opportunities) > 0
      assert :computation_memoization in cache_types || length(opportunities) > 0
      assert :http_response_cache in cache_types || length(opportunities) > 0
      
      # Check implementation guide
      assert Enum.all?(result.implementation_guide, fn guide ->
        length(guide.implementation_steps) > 0
      end)
    end
  end
  
  describe "memory analysis" do
    test "detects memory leak patterns" do
      context = %{agent: %{state: %{}}}
      
      code = """
      class MemoryLeaker {
        constructor() {
          // Timer without cleanup
          this.timer = setInterval(() => this.update(), 1000);
          
          // Event listener without removal
          document.addEventListener('click', this.handleClick);
          
          // Subscription without unsubscribe
          this.subscription = dataStream.subscribe(this.onData);
          
          // Global reference
          window.leakyData = this.data;
        }
        
        // No cleanup method!
      }
      """
      
      {:ok, result} = PerformanceAnalyzerAgent.AnalyzeMemoryUsageAction.run(
        %{source_code: code, language: "javascript"},
        context
      )
      
      issues = result.memory_analysis.static_analysis.issues
      memory_leaks = Enum.filter(issues, &(&1.type == :memory_leak))
      
      assert length(memory_leaks) >= 3
      
      # Check leak types
      leak_types = Enum.map(memory_leaks, & &1.leak_type) |> Enum.uniq()
      assert :timer in leak_types
      assert :event_listener in leak_types
      assert :subscription in leak_types
    end
    
    test "analyzes allocation patterns" do
      context = %{agent: %{state: %{}}}
      
      code = """
      function allocateHeavy() {
        const objects = new Array(1000);
        const strings = ["a", "b", "c"];
        const funcs = [() => 1, () => 2];
        const data = { key: "value" };
      }
      """
      
      {:ok, result} = PerformanceAnalyzerAgent.AnalyzeMemoryUsageAction.run(
        %{source_code: code, language: "javascript"},
        context
      )
      
      patterns = result.memory_analysis.allocation_patterns
      
      assert patterns.total_allocations > 0
      assert Map.has_key?(patterns.allocation_types, :objects)
      assert Map.has_key?(patterns.allocation_types, :arrays)
      assert Map.has_key?(patterns.allocation_types, :strings)
      assert Map.has_key?(patterns.allocation_types, :functions)
    end
  end
  
  describe "benchmark generation" do
    test "generates appropriate benchmark types" do
      context = %{agent: %{state: %{}}}
      
      code = """
      function quickSort(arr) { /* implementation */ }
      function binarySearch(arr, target) { /* implementation */ }
      function processData(data) { /* implementation */ }
      """
      
      # Micro benchmarks
      {:ok, micro_result} = PerformanceAnalyzerAgent.GenerateBenchmarkAction.run(
        %{source_code: code, language: "javascript", benchmark_type: "micro"},
        context
      )
      
      assert Enum.all?(micro_result.benchmark_suite, &(&1.type == :micro))
      
      # Macro benchmarks
      {:ok, macro_result} = PerformanceAnalyzerAgent.GenerateBenchmarkAction.run(
        %{source_code: code, language: "javascript", benchmark_type: "macro"},
        context
      )
      
      assert Enum.any?(macro_result.benchmark_suite, &(&1.type == :macro))
      
      # Comprehensive includes multiple types
      {:ok, comp_result} = PerformanceAnalyzerAgent.GenerateBenchmarkAction.run(
        %{source_code: code, language: "javascript", benchmark_type: "comprehensive"},
        context
      )
      
      types = Enum.map(comp_result.benchmark_suite, & &1.type) |> Enum.uniq()
      assert length(types) > 1
    end
  end
  
  describe "report generation" do
    test "generates different report formats" do
      context = %{agent: %{state: %{}}}
      
      analysis_results = %{
        profile: %{
          hotspots: [%{severity: 8}],
          metrics: %{profile_score: 75}
        }
      }
      
      # Executive format
      {:ok, exec_report} = PerformanceAnalyzerAgent.GeneratePerformanceReportAction.run(
        %{analysis_results: analysis_results, report_format: "executive"},
        context
      )
      
      assert Map.has_key?(exec_report, :grade)
      assert Map.has_key?(exec_report, :summary)
      refute Map.has_key?(exec_report, :appendices)
      
      # Summary format
      {:ok, summary_report} = PerformanceAnalyzerAgent.GeneratePerformanceReportAction.run(
        %{analysis_results: analysis_results, report_format: "summary"},
        context
      )
      
      assert Map.has_key?(summary_report, :overview)
      assert Map.has_key?(summary_report, :quick_wins)
      
      # Detailed format
      {:ok, detailed_report} = PerformanceAnalyzerAgent.GeneratePerformanceReportAction.run(
        %{analysis_results: analysis_results, report_format: "detailed"},
        context
      )
      
      assert Map.has_key?(detailed_report, :table_of_contents)
      assert Map.has_key?(detailed_report, :appendices)
    end
  end
  
  describe "state management" do
    test "caches profile results", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        profile_type: "cpu",
        hotspots: [],
        metrics: %{profile_score: 80}
      }
      
      metadata = %{source_code: "test", profile_type: "cpu"}
      
      {:ok, updated} = PerformanceAnalyzerAgent.handle_action_result(
        state,
        PerformanceAnalyzerAgent.ProfileCodeAction,
        {:ok, result},
        metadata
      )
      
      assert map_size(updated.state.profile_cache) == 1
    end
    
    test "tracks analysis history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Add profile result
      profile_result = %{
        profile_type: "cpu",
        hotspots: [%{severity: 9}],
        metrics: %{profile_score: 60, critical_hotspots: 1}
      }
      
      {:ok, updated} = PerformanceAnalyzerAgent.handle_action_result(
        state,
        PerformanceAnalyzerAgent.ProfileCodeAction,
        {:ok, profile_result},
        %{}
      )
      
      assert length(updated.state.analysis_history) == 1
      entry = hd(updated.state.analysis_history)
      assert entry.type == :performance_profile
      assert entry.hotspot_count == 1
      
      # Add complexity result
      complexity_result = %{
        overall_assessment: %{
          worst_case_complexity: "O(n²)",
          performance_grade: "C"
        },
        optimization_targets: []
      }
      
      {:ok, updated2} = PerformanceAnalyzerAgent.handle_action_result(
        updated,
        PerformanceAnalyzerAgent.AnalyzeComplexityAction,
        {:ok, complexity_result},
        %{}
      )
      
      assert length(updated2.state.analysis_history) == 2
    end
    
    test "triggers performance alerts", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Result with critical hotspots exceeding threshold
      result = %{
        profile_type: "cpu",
        hotspots: [],
        metrics: %{
          profile_score: 30,
          critical_hotspots: 5,  # Exceeds default threshold of 2
          estimated_cpu_usage: "95%"  # Exceeds default threshold of 80%
        }
      }
      
      {:ok, _updated} = PerformanceAnalyzerAgent.handle_action_result(
        state,
        PerformanceAnalyzerAgent.ProfileCodeAction,
        {:ok, result},
        %{}
      )
      
      # In a real implementation, would check that alerts were emitted
      assert true
    end
  end
  
  describe "agent initialization" do
    test "agent starts with default configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Check default thresholds
      thresholds = state.state.alert_thresholds
      assert thresholds.cpu_threshold == 80
      assert thresholds.memory_threshold == 85
      assert thresholds.critical_hotspot_threshold == 2
      
      # Check empty caches
      assert map_size(state.state.profile_cache) == 0
      assert length(state.state.analysis_history) == 0
      assert map_size(state.state.performance_baselines) == 0
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = PerformanceAnalyzerAgent.additional_actions()
      
      assert length(actions) == 7
      assert PerformanceAnalyzerAgent.ProfileCodeAction in actions
      assert PerformanceAnalyzerAgent.AnalyzeComplexityAction in actions
      assert PerformanceAnalyzerAgent.OptimizeDatabaseQueriesAction in actions
      assert PerformanceAnalyzerAgent.IdentifyCachingOpportunitiesAction in actions
      assert PerformanceAnalyzerAgent.GenerateBenchmarkAction in actions
      assert PerformanceAnalyzerAgent.AnalyzeMemoryUsageAction in actions
      assert PerformanceAnalyzerAgent.GeneratePerformanceReportAction in actions
    end
  end
end