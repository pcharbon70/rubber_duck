## Generating Code

Use `list_generators` to list available generators when available, otherwise `mix help`. If you have to run generator tasks, pass `--yes`. Always prefer to use generators as a basis for code generation, and then modify afterwards.

## Tools

Use tidewave MCP tools when available, as they let you interrogate the running application in various useful ways.

## Logs & Tests

When you're done executing code, try to compile the code, and check the logs or run any applicable tests to see what effect your changes have had.

## Use Eval

Use the `project_eval` tool to execute code in the running instance of the application. Eval `h Module.fun` to get documentation for a module or function.

## Ash First

Always use Ash concepts, almost never ecto concepts directly. Think hard about the "Ash way" to do things. If you don't know, often look for information in the rules & docs of Ash & associated packages.

## Code Generation

Start with generators wherever possible. They provide a starting point for your code and can be modified if needed.

## ALWAYS research, NEVER assume

Always use `package_docs_search` to find relevant documentation before beginning work.

## IMPLEMENTATION WORKFLOW ENFORCEMENT

**CRITICAL REMINDER**: When you see requests like "implement section X.X", "let's implement", "start working on":

1. **STOP IMMEDIATELY** - Do not start coding
2. **CREATE FEATURE BRANCH FIRST**: `git checkout -b feature/<section>-<name>`  
3. **VERIFY BRANCH**: `git branch`
4. **FOLLOW FEATURE WORKFLOW**: Go through phases 1-5 properly
5. **NO CODE** until you're on the correct feature branch and have approval

**Common violations to avoid:**
- Writing code on main branch
- Creating files before feature branch
- Skipping the feature plan document
- Starting implementation without approval

## Don't start or stop phoenix applications

Never attempt to start or stop a phoenix application.
Your tidewave tools work by being connected to the running application, and starting or stopping it can cause issues.
