# TEST-DRIVEN DEVELOPMENT (TDD) WORKFLOW

**THIS WORKFLOW IS MANDATORY FOR ALL IMPLEMENTATION TASKS**

**TRIGGER CONDITIONS**: This workflow is automatically triggered by:
- The Feature Implementation Workflow (mandatory integration)
- Any implementation task that involves writing new code
- Any bug fix or modification to existing functionality

## Planning

**When asked to create a or add to an existing plan you must:** 
Follow strict TDD principles - write failing tests first, then minimal 
implementation code, then refactor. Include specific test cases for 
each function before any implementation.

## Plan Structure

Structure your plan around the TDD cycle:

- Break down features into small, testable units
- For each feature, explicitly plan to write failing tests first
- Include specific steps for making tests pass with minimal code
- Plan refactoring phases after each green phase

## Test Ordering

- Test creation should always precede implementation.
- Ensure each step starts with writing tests that fail, then writing just enough code to pass those tests.

## Testing Framework Setup

Make sure your plan includes setting up the testing environment, choosing appropriate testing frameworks, and configuring test runners before any feature development begins.

## Granular steps

Make sure the plan breaks down complex features into small, independently testable units. 
This makes it easier to follow TDD principles without getting overwhelmed.

## Coverage Expectations

- When doing unit tests you should aim for 80 percent coverage
- When doing integration tests you should aim for 90 percent coverage

