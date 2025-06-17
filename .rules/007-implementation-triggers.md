# IMPLEMENTATION TRIGGER RULES

**THESE RULES DETERMINE WHEN WORKFLOWS ARE AUTOMATICALLY TRIGGERED**

## Distributed Implementation Plan Section Triggers

**MANDATORY**: When implementing any section from the distributed implementation plan:

1. **New Phase Section**: Any section like "1.1", "1.2", "2.1", "3.3", etc. MUST trigger the Feature Implementation Workflow
2. **Feature Workflow Cascade**: The Feature Implementation Workflow MUST automatically trigger the TDD Workflow
3. **No Exceptions**: This applies to ALL sections regardless of size or complexity

## Workflow Chain Requirements

```
Implementation Plan Section → Feature Workflow → TDD Workflow
```

**Example Triggers**:
- "Let's implement section 1.1" → Feature Workflow → TDD Workflow
- "Start working on 2.3" → Feature Workflow → TDD Workflow  
- "Begin phase 3.1" → Feature Workflow → TDD Workflow

## Branch Strategy Integration

**MANDATORY**: Before starting any triggered workflow:
1. Create a new feature branch named: `feature/<section>-<description>`
2. Example: `feature/1.1-basic-otp-application-setup`
3. Example: `feature/2.3-performance-optimization-ai-workloads`

## Git Commit Requirements

**MANDATORY**: When creating any git commit:
1. **NO AI REFERENCES**: Never mention AI agents, LLMs, Claude, or any AI tools in commit messages
2. **HUMAN-AUTHORED**: All commit messages must appear as if written by a human developer
3. **NO ATTRIBUTION**: Never include Co-Authored-By tags referencing AI systems
4. **PROFESSIONAL TONE**: Use standard development commit message conventions

## Exceptions

**NO EXCEPTIONS**: All implementation work MUST follow this trigger chain.