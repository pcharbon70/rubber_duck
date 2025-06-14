# WORKFLOW ENFORCEMENT CHECKLIST

**THIS MUST BE THE FIRST THING CHECKED WHEN ANY IMPLEMENTATION REQUEST IS MADE**

## STOP AND CHECK TRIGGERS

When the user says any of these phrases, IMMEDIATELY STOP and run through this checklist:
- "implement section X.X"
- "let's implement"
- "start working on"
- "begin phase"
- "work on section"
- "implement feature"
- "add functionality"
- "create module"
- Any variation of the above

## MANDATORY ENFORCEMENT STEPS

### Step 1: RECOGNIZE THE TRIGGER
**BEFORE DOING ANYTHING ELSE**, when you see an implementation request:
1. STOP
2. Say: "I need to follow the feature workflow for section X.X"
3. DO NOT start coding
4. DO NOT read files related to implementation
5. DO NOT plan the implementation details yet

### Step 2: CREATE FEATURE BRANCH IMMEDIATELY
```bash
# MUST BE YOUR FIRST COMMAND
git checkout -b feature/<section>-<description>
```

### Step 3: CONFIRM BRANCH SWITCH
```bash
# MUST VERIFY you're on the feature branch
git branch
```

### Step 4: START FEATURE WORKFLOW
Only AFTER confirming you're on the feature branch:
1. Begin Phase 1 research
2. Create feature plan document
3. Get approval before implementation

## RED FLAGS TO WATCH FOR

If you find yourself doing ANY of these before creating a feature branch:
- Writing code
- Creating new files
- Modifying existing files
- Running mix commands
- Adding dependencies

**STOP IMMEDIATELY** - You've violated the workflow!

## SELF-CHECK QUESTIONS

Before starting ANY implementation work, ask yourself:
1. Am I on a feature branch? (not main)
2. Have I created the feature plan document?
3. Have I received explicit approval to proceed?
4. Am I following the TDD workflow?

Before ANY git commit, ask yourself:
5. Does my commit message mention AI, LLM, Claude, or myself? (If YES - REMOVE IT!)
6. Does my commit message attribute work to any AI tool? (If YES - REMOVE IT!)

If ANY answer is "no" or violates the rules - STOP and correct it!

## RECOVERY PROCEDURE

If you realize you've started implementation on the wrong branch:
1. STOP all work immediately
2. Stash or commit current changes
3. Create the proper feature branch
4. Move the work to the feature branch
5. Continue following the proper workflow

## REMEMBER

**The feature branch MUST be created BEFORE:**
- Reading implementation files
- Planning code structure  
- Writing any code
- Running any mix commands
- Adding any dependencies

**NO EXCEPTIONS!**