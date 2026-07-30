AGENTS.md

CallDesk

AI development instructions for the CallDesk project.

⸻

Project Mission

CallDesk is a lightweight, offline-first calling application for iPhone and iPad.

The goal is to let frontline staff complete a calling action with a single tap.

Everything in this project should prioritize:

* Speed
* Simplicity
* Reliability
* Native Apple experience

Do not introduce unnecessary complexity.

⸻

Technology

Platform

* iOS 16+

Language

* Swift 6

UI

* SwiftUI only

UIKit should only be used when SwiftUI cannot reasonably achieve the required functionality.

Architecture

* MVVM
* Feature-first project structure
* Async/Await
* Protocol-oriented design where appropriate

Persistence

* Core Data

Persistence must be abstracted behind a data layer.

Views must never directly access Core Data.

⸻

Design Principles

When making implementation decisions always prefer:

* Native APIs
* Small components
* Clear code
* Readability
* Maintainability

Avoid:

* Over engineering
* Third-party dependencies unless absolutely necessary
* Global mutable state
* Massive ViewModels
* Business logic inside Views

⸻

User Experience

The application should always feel immediate.

Calling someone is the primary action.

A normal calling workflow should require only:

Open Board

↓

Tap Item

↓

Voice Plays

↓

State Updates

↓

Ready For Next Call

No unnecessary dialogs.

No loading screens.

No waiting.

⸻

Feature Priorities

Priority 1

* Call boards
* Call items
* Voice calling
* Status colors
* Drag sorting
* Local persistence

Priority 2

* Batch generation
* Voice templates
* Call history
* Search
* Settings

Priority 3

* Import / Export
* Cloud sync
* External display
* AirPlay
* Remote control

Never implement Priority 3 features before Priority 1 is complete.

⸻

Project Structure

CallDesk
App/
Components/
Features/
Models/
Services/
Persistence/
Resources/
Utilities/

Each feature should contain:

Feature
Views
ViewModels
Models (if needed)
Services (if needed)

Keep features independent whenever possible.

⸻

View Rules

Views should:

* Render UI
* Forward user actions
* Observe ViewModels

Views should never contain:

* Business rules
* Data persistence
* Voice logic
* Sorting logic

⸻

ViewModel Rules

ViewModels should:

* Own screen state
* Handle user interaction
* Coordinate Services
* Coordinate Persistence

Keep ViewModels focused.

If a ViewModel becomes too large, extract Services.

⸻

Services

Services contain reusable business logic.

Examples:

* VoiceService
* CallService
* ImportService
* ExportService

Services should not know about SwiftUI.

⸻

Persistence

Core Data should be hidden behind protocols.

Avoid exposing NSManagedObject to Views.

Prefer plain Swift models when communicating with ViewModels.

⸻

Naming

Use Apple’s naming conventions.

Types

PascalCase

Variables

camelCase

Enums

PascalCase

Enum cases

camelCase

Avoid abbreviations.

Choose descriptive names.

⸻

Code Style

Prefer:

* Small files
* Small methods
* One responsibility per type

Avoid:

* Long functions
* Deep nesting
* Duplicate code
* Force unwraps
* Magic numbers

Favor early return.

⸻

Voice Calling

The default implementation uses:

AVSpeechSynthesizer

Every call action should:

1. Play notification sound.
2. Speak text.
3. Update status.
4. Save history.
5. Refresh UI immediately.

Voice playback must support interruption and replay.

⸻

Performance

The application should remain responsive with large datasets.

Prefer:

* LazyVGrid
* Lazy stacks
* Background tasks when appropriate

Avoid unnecessary redraws.

⸻

Accessibility

Every feature should support:

* Dynamic Type
* VoiceOver
* Dark Mode
* Reduce Motion

Accessibility is not optional.

⸻

Dependencies

Before adding any third-party library ask:

1. Can Apple APIs solve this?
2. Does the dependency reduce long-term maintenance?
3. Is it actively maintained?

If the answer is no, do not add it.

⸻

Pull Request Checklist

Before considering work complete:

* Project builds successfully
* No compiler warnings
* No duplicated code
* Naming follows project conventions
* Architecture remains consistent
* New code is testable

⸻

Guiding Principle

When multiple implementations are possible, always choose the one that is:

* Simpler
* More maintainable
* More native
* Easier to understand

Optimize for long-term maintainability rather than short-term convenience.//
//  AGENTS.md
//  CallDesk
//
//  Created by 何玮 on 2026/7/30.
//


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
