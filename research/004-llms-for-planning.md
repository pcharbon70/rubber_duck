# LLMs for Planning: A Comprehensive Research Report for RubberDuck

Large language models have evolved from simple text generators to sophisticated reasoning systems, yet recent research reveals a critical insight: LLMs cannot autonomously plan with only 12% success rates, but excel when integrated into hybrid planning frameworks. This fundamental understanding, combined with breakthrough reasoning models and practical implementations, offers clear pathways for enhancing RubberDuck's planning capabilities.

## The planning paradox and its solution

The field experienced a paradigm shift in 2024 with Subbarao Kambhampati's **LLM-Modulo framework**, presented at ICML 2024. This research demonstrated that while LLMs fail at autonomous planning, they excel as components within structured planning systems. The framework combines LLM generation with external model-based critics - hard critics verify correctness using tools like VAL for PDDL, while soft critics evaluate style and preferences. This bidirectional interaction creates continuous feedback loops that achieve dramatically better results than LLMs alone.

The implications are profound: rather than expecting LLMs to plan independently, successful systems leverage their strengths in natural language understanding, pattern recognition, and idea generation while compensating for their weaknesses through external validation, constraint checking, and logical reasoning systems.

## State-of-the-art techniques transforming planning

The technical landscape of LLM planning revolves around several core prompting strategies, each addressing different aspects of the planning challenge. **Chain-of-Thought (CoT)** prompting, introduced by Wei et al. in 2022, enables complex reasoning by generating intermediate steps. Advanced variations include Self-Consistent CoT, which generates multiple reasoning paths and selects the most consistent answer, achieving up to 52.99% accuracy improvements on scientific reasoning tasks.

**Tree-of-Thought (ToT)** prompting extends this by exploring multiple reasoning paths simultaneously with backtracking capabilities. On complex tasks like the Game of 24, ToT achieves 74% success compared to just 4% with standard CoT. **Graph-of-Thought (GoT)** further advances this concept by modeling reasoning as arbitrary graphs where thoughts are vertices and dependencies are edges, enabling non-linear reasoning patterns that better capture human-like thinking.

The **ReAct framework** synergizes reasoning traces with task-specific actions, creating a dynamic planning and execution loop. This pattern of Thought → Action → Observation → Updated Thought has proven particularly effective in interactive environments, achieving 34% improvement in ALFWorld and 10% in WebShop tasks.

For software development specifically, techniques like **ADaPT (As-Needed Decomposition and Planning)** provide recursive decomposition that adapts to both task complexity and LLM capability. This achieved 28.3% higher success rates in ALFWorld, 27% in WebShop, and 33% in TextCraft by explicitly planning and decomposing complex sub-tasks only when needed.

## OpenAI's reasoning revolution

September 2024 marked a breakthrough with OpenAI's **o1 series**, the first models trained with reinforcement learning to "think before responding." These models use internal reasoning tokens to work through problems step-by-step, achieving 74% success on AIME math problems compared to 12% for GPT-4o. While they still struggle with spatial reasoning and long-term planning, maintaining a 54% false positive rate on unsolvable planning problems, they represent a fundamental advance in LLM reasoning capabilities.

The o1 models demonstrate that training LLMs to inherently reason, rather than prompting them to think, dramatically improves planning performance. However, the opacity of reasoning tokens presents challenges for debugging and validation - a critical consideration for development tools.

## Practical implementations demonstrating real value

The research reveals numerous successful implementations that translate theoretical advances into practical tools. **Microsoft's CodePlan** addresses repository-level coding using adaptive planning algorithms combined with LLMs. It handles complex tasks like package migration across 2-97 files through multi-step chain-of-edits generation, achieving 5/6 repositories passing validity checks versus 0/6 for baseline approaches.

**Plandex**, an open-source AI coding agent, demonstrates practical planning architecture with its two-phase interaction model. Chat mode enables idea exploration while Tell mode executes detailed planning. It handles up to 2M tokens of context directly and can index directories with 20M+ tokens using tree-sitter project maps, all while maintaining a cumulative diff review sandbox for safe code changes.

**AutoCodeRover** achieves impressive 37.3% task resolution in SWE-bench lite through its two-stage approach combining context retrieval with patch generation. Its Program Structure Aware code search APIs navigate codebases efficiently, costing less than $0.7 per task completion.

Commercial tools have also advanced significantly. **GitHub Copilot Workspace** introduced a task-oriented development environment with natural language task specification and multi-step plan generation. The Spec → Plan → Implementation workflow with editable plans and automatic versioning demonstrates effective human-AI collaboration. Similarly, **Cursor IDE** implements task decomposition through .cursorrules files with a multi-agent architecture separating planning from execution.

## Integration approaches for coding assistants

Successful implementations reveal common architectural patterns essential for effective planning systems. **Hierarchical task decomposition** breaks complex tasks into manageable subtasks, while **context-aware planning** uses repository structure and dependencies to inform decisions. **Multi-agent collaboration** separates planning and execution responsibilities, and **iterative refinement** enables continuous plan validation and adjustment.

The most effective systems implement **two-phase approaches** with context retrieval followed by plan generation. They use **agentic loops** following the pattern of Planning → Execution → Validation → Iteration. **Tool integration** provides APIs for code search, file manipulation, and testing, while **symbolic-neural hybrid** approaches combine the strengths of both paradigms.

For Elixir-based systems like RubberDuck, several patterns prove particularly relevant. Repository-level planning from CodePlan handles multi-file changes effectively. Plandex's incremental context loading manages large codebases efficiently. AST-based analysis can leverage Elixir's syntax tree for structure-aware planning, while OTP principles should guide planning integration with application architecture.

## Challenges demanding innovative solutions

Despite remarkable progress, significant challenges remain. LLMs struggle with **autonomous planning**, achieving only ~12% success rates without external support. They exhibit poor performance on **spatially complex tasks** and have difficulty recognizing **unsolvable problems**. The **opacity of reasoning tokens** in advanced models like o1 creates debugging challenges, while **context window limitations** constrain planning scope.

**Integration complexity** poses practical challenges, from workflow integration to tool compatibility across environments. Security concerns arise with code transmission, while computational costs of reasoning tokens impact scalability. These limitations underscore the importance of hybrid approaches that leverage LLM strengths while compensating for weaknesses.

## Recent developments reshaping the landscape

The 2023-2025 period witnessed explosive growth in LLM planning capabilities. Beyond the LLM-Modulo framework and o1 series, numerous advances emerged. Survey papers like "Understanding the planning of LLM agents" (February 2024) and "PlanGenLLMs" (February 2025) established comprehensive taxonomies and evaluation frameworks focusing on completeness, executability, optimality, representation, generalization, and efficiency.

The AI coding assistant market, valued at $4.86 billion in 2023 and growing at 27.1% annually, reflects rapid adoption with 76% of developers using or planning to use these tools. New entrants like Amazon Q Developer evolved from CodeWhisperer with multi-agent orchestration for complex workflows. Google's Gemini Code Assist offers multimodal assistance with planning capabilities, while tools like Jules provide asynchronous AI coding agents for autonomous feature planning.

Benchmark development accelerated with **PlanBench** providing comprehensive evaluation frameworks and **ACPBench** covering 11 classical planning domains. These benchmarks evaluate plan validation, action reachability, and landmark recognition across 22 state-of-the-art LLMs, establishing rigorous standards for assessing planning capabilities.

## Implementing planning in RubberDuck

Based on this research, RubberDuck can enhance its existing CoT, RAG, and self-correction capabilities with sophisticated planning features through several strategic implementations:

**1. Adopt the LLM-Modulo architecture**: Implement external critics for plan validation, combining Elixir-based hard critics for syntactic and semantic validation with LLM-based soft critics for style and convention checking. This hybrid approach leverages RubberDuck's existing capabilities while adding robust planning validation.

**2. Enhance Chain-of-Thought with planning-specific prompts**: Extend the existing CoT implementation with Self-Consistent CoT for improved reliability. Implement planning-specific CoT templates that guide task decomposition, dependency identification, resource allocation, timeline estimation, and risk assessment.

**3. Implement Tree-of-Thought for complex planning**: For scenarios requiring exploration of multiple solution paths, integrate ToT capabilities. This proves particularly valuable for architectural decisions, refactoring strategies, and complex feature implementations where multiple valid approaches exist.

**4. Create a ReAct-based execution framework**: Develop an execution engine that follows the Thought → Action → Observation pattern, integrating with Elixir's Mix tasks, ExUnit for testing, and existing development tools. This enables dynamic plan adjustment based on execution results.

**5. Build repository-level planning capabilities**: Implement CodePlan-inspired features for multi-file changes, using Elixir's AST for structure-aware planning. Create dependency graphs for understanding code relationships and impact analysis. This addresses real-world development scenarios beyond single-file modifications.

**6. Develop an iterative refinement system**: Implement self-refinement loops that critique and improve generated plans. Use RubberDuck's existing self-correction capabilities as a foundation, extending them specifically for plan validation and improvement.

**7. Design Elixir-specific planning primitives**: Create planning templates aware of OTP principles, GenServer patterns, and supervision trees. Integrate with Phoenix for web application planning and leverage Ecto for database-related planning tasks.

**8. Implement progressive planning complexity**: Start with simple task decomposition for straightforward problems, escalate to ToT for complex architectural decisions, and reserve GoT-style approaches for highly interconnected system designs.

## Future-proofing RubberDuck's planning capabilities

The research points toward several emerging trends that RubberDuck should consider for long-term success. **Neurosymbolic planning frameworks** combining neural and symbolic reasoning will likely dominate future systems. **Multimodal planning** integrating visual inputs with code understanding offers new possibilities for design-to-code workflows. **Reinforcement learning integration** promises self-improving planning systems that learn from execution outcomes.

The shift toward **local deployment** for privacy-preserving solutions aligns well with RubberDuck's architecture. **Transparency** in planning decisions becomes increasingly critical as these systems handle more complex tasks. **Human-AI collaboration** patterns that maintain developer control while leveraging AI capabilities will define successful tools.

## Strategic recommendations for immediate implementation

RubberDuck should prioritize implementing the LLM-Modulo architecture with Elixir-based critics, as this addresses the fundamental limitation of LLM planning while building on existing strengths. Enhancing the current CoT implementation with Self-Consistent CoT and planning-specific templates provides immediate value with minimal architectural changes.

Development of a ReAct-based execution framework integrated with Mix tasks creates a powerful foundation for dynamic planning. Repository-level planning capabilities address real-world development needs beyond toy examples. These implementations position RubberDuck at the forefront of AI-assisted development tools while maintaining the reliability and transparency developers require.

The key insight from this research is clear: successful LLM planning systems don't expect models to plan autonomously but instead orchestrate their capabilities within structured frameworks. By embracing this hybrid approach, RubberDuck can deliver sophisticated planning features that genuinely enhance developer productivity while avoiding the pitfalls of over-relying on LLM capabilities. The combination of theoretical understanding, practical implementations, and emerging techniques provides a robust foundation for building planning features that developers will trust and value.
