categories = %{
  "Unused Aliases" => 6,
  "Unused Variables (Simple)" => 4,
  "Unused Variables (Shadow Warning)" => 11,
  "Pattern Matching Issues" => 8,
  "Other Warnings" => 10
}

IO.puts("=== Code Analysis Module Warning Categories ===\n")

IO.puts("1. Unused Aliases: 6")
IO.puts("   - AST alias in common.ex, semantic.ex, security.ex, style.ex")
IO.puts("   - Common alias in semantic.ex, security.ex")
IO.puts("   - Workspace alias in analyzer.ex")

IO.puts("\n2. Unused Variables (Shadow Warning): 11")
IO.puts("   - 'issues' variable shadowing (8 occurrences)")
IO.puts("   - 'func_issues' variable shadowing (3 occurrences)")

IO.puts("\n3. Unused Variables (Simple): 4") 
IO.puts("   - 'config' in semantic.ex")
IO.puts("   - 'issues' in semantic.ex")
IO.puts("   - 'ast_info' in semantic.ex and style.ex")
IO.puts("   - 'file_path' in analyzer.ex")

IO.puts("\n4. Pattern Matching Issues: ~8 (from other modules)")
IO.puts("   - Clauses that will never match")
IO.puts("   - Cond clauses that are unreachable")

IO.puts("\n5. Other Warnings: ~10 (from other modules)")
IO.puts("   - Ash resource warnings")
IO.puts("   - Reactor.new/1 undefined")
IO.puts("   - Type system warnings")

IO.puts("\n=== Total Warnings in Analysis Modules: ~21 ===")
IO.puts("=== Total Warnings Overall: ~39 ===")
