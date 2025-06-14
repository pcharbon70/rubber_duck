# FEATURE IMPLEMENTATION WORKFLOW

**THIS IS A MANDATORY WORKFLOW - NO STEPS CAN BE SKIPPED**

**TRIGGER CONDITIONS**: This workflow is automatically triggered when:
- Implementing any new section (e.g., 1.1, 1.2, 2.1, etc.) from the distributed implementation plan
- Adding any new feature functionality
- Creating new modules or major functionality

**MANDATORY TDD INTEGRATION**: This workflow MUST trigger the TDD workflow for all implementation tasks.

## PHASE 1: RESEARCH & PLANNING (MANDATORY)

### Step 1.1: Initial Research
**YOU MUST USE ALL AVAILABLE RESOURCES**:
- Check existing usage rules via `get_usage_rules` MCP tool or CLAUDE.md links
- Use `package_docs_search` for ALL potentially relevant packages
- Read the full documentation found
- Search for similar features in the codebase using grep/glob
- Check for existing patterns to follow
- Use `project_eval` to explore modules if available
- Review any applicable existing usage rules for packages you'll be working with

### Step 1.2: Requirements Analysis
**REQUIRED ACTIONS**:
1. List ALL requirements explicitly
2. Identify edge cases and limitations
3. Check for security implications
4. Verify compatibility with Ash patterns
5. Document assumptions that need validation

### Step 1.3: Create Feature Plan Document
**CREATE FILE**: `<project_root>/notes/features/<number>-<name>.md` (inside the project directory)

### Step 1.4: Create and Switch to Feature Branch
**MANDATORY BEFORE ANY IMPLEMENTATION**:
1. Create feature branch: `git checkout -b feature/<section-number>-<feature-name>`
2. Example: `git checkout -b feature/1.3-initial-clustering-infrastructure`
3. Verify you are on the feature branch: `git branch`
4. ALL implementation work MUST happen on this feature branch
5. Keep main branch clean for other work

**MANDATORY STRUCTURE**:
```markdown
# Feature: <Feature Name>

## Summary
[1-2 sentences describing the feature]

## Requirements
- [ ] Requirement 1 (specific and measurable)
- [ ] Requirement 2
- [ ] etc.

## Research Summary
### Existing Usage Rules Checked
- Package X existing usage rules: [key rules that apply]
- Package Y existing usage rules: [key rules that apply]

### Documentation Reviewed
- Package X: [what you found]
- Package Y: [what you found]

### Existing Patterns Found
- Pattern 1: [file:line] description
- Pattern 2: [file:line] description

### Technical Approach
[Detailed explanation of HOW you will implement this]
k
## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Risk 1 | High/Med/Low | How to handle |
k
## Implementation Checklist
- [ ] Task 1 (specific file/module to create/modify)
- [ ] Task 2
- [ ] Test implementation
- [ ] Verify no regressions

## Questions  
1. [Any clarifications needed]
```

## PHASE 2: APPROVAL CHECKPOINT (MANDATORY)

**YOU MUST STOP HERE**:
1. Present the plan document
2. Confirm you are on the correct feature branch
3. Explicitly ask: "Please review this plan. Should I proceed with implementation?"
4. WAIT for explicit approval
5. Do NOT proceed without approval

## PHASE 3: IMPLEMENTATION

### Step 3.1: Set Up Tracking
**REQUIRED**:
1. Use TodoWrite to create tasks from implementation checklist
2. Update `<project_root>/notes/features/<number>-<name>.md` with a `## Log` section
3. Log EVERY significant decision or discovery

### Step 3.2: Implementation Rules
**MANDATORY SEQUENCE FOR EACH TASK**:
1. **APPLY TDD WORKFLOW**: Follow the complete TDD workflow (write failing tests first, then minimal implementation, then refactor)
2. Check for relevant generator using `list_generators`
3. Run generator with `--yes` if exists
4. Research docs again for specific implementation details
5. Write failing tests BEFORE any implementation code
6. Implement minimal code to make tests pass
7. Refactor if needed while keeping tests green
8. Compile and check for errors
9. Ensure all tests pass
10. Update log with results

### Step 3.3: Progress Reporting
**AFTER EACH SUBTASK**:
1. Report what was done
2. Show any errors/warnings
3. Update todo status
4. Ask if you should continue

## PHASE 4: FINALIZATION

### Step 4.1: Verification
**REQUIRED CHECKS**:
1. All requirements met (check against original list)
2. All tests passing
3. No compilation warnings
4. Code follows Ash patterns

### Step 4.2: Documentation Update
**UPDATE** `<project_root>/notes/features/<number>-<name>.md`:
1. Add `## Final Implementation` section
2. Document what was built
3. Note any deviations from plan
4. List any follow-up tasks needed

## PHASE 5: COMPLETION CHECKPOINT

**FINAL REQUIREMENTS**:
1. Present summary of implementation
2. Show test results
3. Ensure all changes are committed on feature branch
4. Ask: "Feature implementation complete. Ready to create pull request?"
5. WAIT for confirmation before creating pull request or merging to main

# REMEMBER

- **NO COMMITS** unless explicitly told "commit this"
- **RESEARCH FIRST** - always use package_docs_search
- **ASH PATTERNS ONLY** - no direct Ecto
- **STOP AT CHECKPOINTS** - wait for approval
- **LOG EVERYTHING** - maintain feature notes file
