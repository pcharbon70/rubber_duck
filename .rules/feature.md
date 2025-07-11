# FEATURE IMPLEMENTATION WORKFLOW

**THIS IS A MANDATORY WORKFLOW - NO STEPS CAN BE SKIPPED**

## PHASE 1: RESEARCH & PLANNING (MANDATORY)

### Step 1.1: Initial Research
**YOU MUST USE ALL AVAILABLE RESOURCES**:
- Check existing usage rules via `get_usage_rules` MCP tool or CLAUDE.md links
- Use `hexdocs` for ALL potentially relevant packages
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
6. Consider whether or not this feature is truly necessary as specified. Consider alternatives, or if the feature may do more harm than good, and pushback if necessary.

### Step 1.3: Create Feature Plan Document
**CREATE FILE**: `<project_root>/notes/features/<number>-<name>.md` (inside the project directory)

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

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Risk 1 | High/Med/Low | How to handle |

## Implementation Checklist
- [ ] Task 1 (specific file/module to create/modify)
- [ ] Task 2
- [ ] Test implementation
- [ ] Verify no regressions

## Questions for Zach
1. [Any clarifications needed]
```

## PHASE 2: APPROVAL CHECKPOINT (MANDATORY)

**YOU MUST STOP HERE**:
1. Present the plan document
2. Explicitly ask: "Please review this plan. Should I proceed with implementation?"
3. WAIT for explicit approval
4. Do NOT proceed without approval

## PHASE 3: IMPLEMENTATION

MANDATORY BEFORE ANY IMPLEMENTATION:

1. Create feature branch: git checkout -b feature/<section-number>-<feature-name>
2. Example: git checkout -b feature/1.3-initial-clustering-infrastructure
3. Verify you are on the feature branch: git branch
4. ALL implementation work MUST happen on this feature branch
5. Keep main branch clean for other work

### Step 3.1: Set Up Tracking
**REQUIRED**:
1. Use TodoWrite to create tasks from implementation checklist
2. Update `<project_root>/notes/features/<number>-<name>.md` with a `## Log` section
3. Log EVERY significant decision or discovery

### Step 3.2: Write at least one failing test
1. Create a test in the most idiomatic place, or create a new test.
2. Write a failing test that demonstrates the desired behavior.
3. Run the test and ensure it fails.

### Step 3.3: Implementation Rules
**MANDATORY SEQUENCE FOR EACH TASK**:
1. Check for relevant generator using `list_generators`
2. Run generator with `--yes` if exists
3. Research docs again for specific implementation details
4. Implement using Ash patterns ONLY
5. Compile and check for errors
6. Run tests if applicable
7. Update log with results

### Step 3.4: Progress Reporting
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
3. Write summary of implementation in `<project_root>/notes/features/<number>-<name>-summary.md`

# REMEMBER

- **NO COMMITS** unless explicitly told "commit this"
- **RESEARCH FIRST** - always use package_docs_search
- **ASH PATTERNS ONLY** - no direct Ecto
- **STOP AT CHECKPOINTS** - wait for approval
- **LOG EVERYTHING** - maintain feature notes file
