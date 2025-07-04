
# Evaluation Metrics for LLM Coding Tools in Elixir

This document explores automated, repeatable metrics commonly used to evaluate the performance of large language model (LLM) coding tools, and how they can be applied in the development and CI/CD pipelines of an Elixir-based coding assistant.

---

## 🔢 Key Metrics

| Metric                     | Measures                              | Notes |
|---------------------------|----------------------------------------|-------|
| **Pass@k**                | Functional correctness over k samples | Standard in LLM code eval (e.g., HumanEval) |
| **Exact Match Accuracy**  | Textual match to reference code       | Very strict, not tolerant to variations |
| **CodeBLEU**              | Structural + semantic similarity      | More tolerant and human-correlated |
| **Functional Test Rate**  | % of tests passed by generated code   | Granular and language-agnostic |
| **Compilation Success**   | Does the code compile/run?            | Quick check for syntactic validity |
| **Static Analysis & Coverage** | Code quality and line coverage    | Optional, but useful in CI/CD |

---

## 🎯 1. Pass@k

**Definition:** Probability that at least one of the top-*k* generated outputs passes all unit tests.

**Formula:**
\[
	ext{pass}@k = 1 - rac{inom{n-c}{k}}{inom{n}{k}}
\]

**How to Use in Elixir:**
- Define ExUnit tests for problems.
- Generate `k` solutions with the assistant.
- Compile & run each through ExUnit.
- Count how many problems had at least one pass.

**CI/CD Integration:**
- Script with `mix` tasks and Oban jobs.
- Fail build if `pass@1` drops below threshold.

---

## 📏 2. Exact Match Accuracy

**Definition:** Percentage of outputs that match reference code exactly.

**Pros:** Simple, binary match.

**Cons:** Overly strict, no credit for valid variants.

**Use in Elixir:**
- Compare output to a gold `.ex` file via string equality.
- Mostly useful for toy problems.

---

## 💡 3. CodeBLEU

**Definition:** Combines BLEU + AST structure + data-flow + keyword matching.

**Pros:** Matches syntax & semantics, closer to human judgment.

**Cons:** No Elixir-native implementation. Needs AST comparison.

**Workaround:**
- Use `Code.string_to_quoted/1` to get AST.
- Optionally call Python CodeBLEU via CLI with stringified code.

---

## ✅ 4. Functional Test Pass Rate

**Definition:** How many tests passed out of all.

- **Task pass rate:** All tests pass = 1, else 0.
- **Test case accuracy:** % of assertions passed.

**In Elixir:**
- Use ExUnit for unit tests.
- Aggregate pass/fail from generated modules.

**CI/CD Use:**
- Require a certain % of task/test case pass rate.

---

## 🧪 5. Compilation and Runtime Success

**Definition:** Code compiles and runs without errors.

**How to Measure:**
- Use `Code.string_to_quoted/1` or `mix compile`.
- Catch runtime errors during test execution.

**CI/CD Use:**
- Fail build on compilation error.
- Track % of code that compiles.

---

## 🧰 6. Static Analysis & Test Coverage

**Tools:**
- [`Credo`](https://github.com/rrrene/credo) – code style
- [`Dialyzer`](https://github.com/jeremyjh/dialyxir) – type analysis
- [`ExCoveralls`](https://github.com/parroty/excoveralls) – test coverage

**Use in CI:**
```bash
mix credo --strict
mix dialyzer
mix coveralls
```

---

## 🔄 CI/CD Integration Example

```yaml
- uses: erlef/setup-beam@v1
- run: mix deps.get
- run: mix test --cover
- run: mix credo --strict
- run: mix dialyzer
- run: mix evaluate_llm  # custom Mix task
```

---

## 📌 Summary

| Metric               | Type          | Strengths                         |
|----------------------|---------------|-----------------------------------|
| Pass@k               | Functional    | High-quality correctness          |
| Exact Match          | Textual       | Fast, strict                      |
| CodeBLEU             | Structural    | Semantic & structural correlation |
| Test Pass Rate       | Functional    | Granular, partial scoring         |
| Compile Success      | Syntactic     | Fast validation                   |
| Static Analysis      | Quality       | Maintains idiomatic code          |

---

## 📚 References

- [DSPy](https://arxiv.org/abs/2401.10050)
- [HumanEval](https://github.com/openai/human-eval)
- [CodeBLEU Paper](https://arxiv.org/abs/2009.10297)
- [Aider](https://github.com/paul-gauthier/aider)
- [LangChain Elixir](https://github.com/tyler-eon/langchain-elixir)


