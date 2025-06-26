# Feature: Convert to Umbrella Project Structure

## Summary
Convert the existing RubberDuck single Mix project into an umbrella project structure with four separate applications as specified in the implementation plan.

## Requirements
- [ ] Convert existing single application to umbrella structure without losing functionality
- [ ] Create four separate apps: rubber_duck_core, rubber_duck_web, rubber_duck_engines, rubber_duck_storage
- [ ] Preserve existing code and tests in appropriate apps
- [ ] Ensure all apps can compile independently
- [ ] Maintain inter-app communication capabilities
- [ ] Update configuration structure for umbrella format

## Research Summary
### Existing Usage Rules Checked
- No specific package usage rules apply to umbrella conversion (built-in Mix feature)

### Documentation Reviewed
- Mix documentation indicates umbrella projects use a root mix.exs with `apps_path: "apps"`
- Each app has its own mix.exs with independent dependencies
- Apps can depend on each other via `in_umbrella: true`

### Existing Patterns Found
- Current project is a simple Mix application with minimal code (lib/rubber_duck.ex)
- Uses standard Mix project structure
- Has one dependency: igniter ~> 0.6

### Technical Approach
1. Create new umbrella structure with root mix.exs
2. Move existing project into a temporary directory
3. Create four new apps using `mix new` within apps/ directory
4. Migrate existing code to appropriate apps:
   - Move lib/rubber_duck.ex to apps/rubber_duck_core/lib/
   - Move tests to apps/rubber_duck_core/test/
5. Update dependencies and configurations
6. Ensure all apps compile and tests pass

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Loss of existing code/git history | High | Create backup, preserve .git directory |
| Broken dependencies | Medium | Update deps in appropriate app mix.exs files |
| Configuration issues | Medium | Carefully migrate configs to umbrella structure |
| Test failures | Low | Move tests with their corresponding code |

## Implementation Checklist
- [ ] Create backup of current project state
- [ ] Create new umbrella root structure
- [ ] Generate apps/rubber_duck_core application
- [ ] Generate apps/rubber_duck_web application  
- [ ] Generate apps/rubber_duck_engines application
- [ ] Generate apps/rubber_duck_storage application
- [ ] Migrate existing code to rubber_duck_core
- [ ] Update root mix.exs for umbrella configuration
- [ ] Update app-specific mix.exs files
- [ ] Verify all apps compile
- [ ] Run existing tests in new structure
- [ ] Update .formatter.exs for umbrella structure
- [ ] Update README.md to reflect new structure

## Questions for Pascal
1. Should the existing RubberDuck module remain in rubber_duck_core or be split across apps?
2. Do you want to preserve the current git history through this conversion?
3. Are there specific dependencies you know will be needed for each app?
4. Should I set up inter-app dependencies now or wait until needed?

## Log
- Created todo tasks for implementation tracking
- Starting implementation phase
- Created backup of existing files
- Created umbrella root structure with apps_path: "apps"
- Generated all four apps successfully
- Migrated existing code to rubber_duck_core
- Fixed directory structure issues (apps were initially nested incorrectly)
- Updated mix.exs files for proper umbrella configuration
- All apps compile successfully
- All tests pass (4 apps, 8 tests total)
- Updated .formatter.exs for umbrella structure
- Updated README.md with new project structure

## Final Implementation
Successfully converted the RubberDuck project from a single Mix application to an umbrella project with four applications:
- rubber_duck_core: Contains the original RubberDuck module and tests
- rubber_duck_web: Empty app with supervisor, ready for Phoenix integration
- rubber_duck_engines: Empty app with supervisor, ready for analysis engines
- rubber_duck_storage: Empty app with supervisor, ready for Ecto integration

All apps are properly configured with:
- Shared deps, build, and config paths
- Individual mix.exs files
- Proper supervision trees (web, engines, storage have Application modules)
- Working test suites

No deviations from the original plan. The conversion preserved all existing functionality and git history.