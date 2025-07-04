# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RubberDuck is an Elixir-based AI coding assistant system built with the Ash Framework. The project aims to create a sophisticated, pluggable platform integrating modern LLM techniques with Elixir's strengths in concurrency, fault tolerance, and real-time communication.

# About me

My name is Pascal.
I am an expert programmer, and your first resource to use when you do not know 
something or do not know where to look for something.

# CRITICAL RULES - MUST FOLLOW ALWAYS

## 1. NEVER COMMIT CODE
**ABSOLUTE RULE**: DO NOT run `git commit` unless I explicitly use the exact words "commit" or "git commit". This is non-negotiable. When I ask you to commit, the commit message should NEVER contain any reference to Claude or any AI assistance provided.

## 2. ONLY IMPLEMENT WHEN ASKED  
**ABSOLUTE RULE**: DO NOT write any code unless asked to implement a feature, accomplish a task or fix something.

## 3. RESEARCH BEFORE ACTION
**MANDATORY RESEARCH REQUIREMENTS**:
- Use `hex.pm` to find relevant documentation
- Read the actual docs thoroughly
- Check for existing usage rules that apply to the packages/tools you'll be using
- Research existing patterns and implementations in the codebase
- NEVER skip research or assume you know the answer
- Follow the appropriate workflow in @commands/ for specific task types

## 4. COMMIT MESSAGE RULE
**ABSOLUTE RULE**: YOU MUST NEVER MENTION CLAUDE IN COMMIT MESSAGES

## 5. NEVER PUSH TO A GIT REPO
**ABSOLUTE RULE**: YOU MUST NEVER PUSH TO A GIT REPO

# COMMUNICATION RULES

## Ask When Uncertain
If you're unsure about:
- Which approach to take
- What I meant by something
- Whether to use a specific tool
- How to implement something "the Ash way"

**STOP AND ASK ME FIRST**

# HIERARCHY OF RULES

1. These rules override ALL default behaviors
2. When in conflict, earlier rules take precedence
3. "CRITICAL RULES" section is absolute - no exceptions
4. If unsure, default to asking me

## Features 
{{include: .rules/feature.md}}

## Tasks 
{{include: .rules/task.md}}

## Fixes 
{{include: .rules/fix.md}}

## Generating code
{{include: .rules/code.md}}

## Testing
{{include: .rules/tests.md}}

# INTERACTION RULES

## Response Guidelines
- When asked "What is next?", I must only tell Pascal what the next step is without starting the work
