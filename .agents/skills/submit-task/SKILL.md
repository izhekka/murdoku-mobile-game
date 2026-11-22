---
name: submit-task
description: Use when the user asks for any kind of change to the app or repo — a feature, fix, tweak, refactor, or content edit, however small or casually phrased ("can you fix…", "add…", "change…", "improve…", "make it…") — and when explicitly asked to submit, file, dispatch, or hand off work ("submit this as a task", "turn this into an issue", "break this down for the executors"). Agents never start making changes on a direct user ask: every change request runs the brainstorm → spec → issue cycle below.
---

# Submit Task

Turn a change request into executor-ready GitHub issues through a fixed cycle: **brainstorm → spec → file**. Executors read these issues in isolation, with no access to this conversation — the issue must carry the full analysis. The output structure is deterministic: identical sections, identical order, on every issue.

## 1. The hard rule: never start changes on a direct ask

- When the user asks for any kind of change — feature, bugfix, tweak, refactor, copy, however small or casually phrased — do NOT edit files, write code, or fix anything directly. Run the cycle below instead.
- The only work allowed before an approved spec is reading and exploring the repo.
- Explicit hand-off asks ("submit this as a task", "file an issue for this") enter the same cycle; there is no fast path that skips the questions and the spec.
- Informational asks (questions, explanations, status reports) do not trigger this cycle.
- If the user pushes to skip ahead ("just do it", "it's tiny"), fall back to brainstorming's own escape hatch: make the how-it-gets-made calls in one plain line, state the short design (scope, acceptance criteria, testing strategy) and get an explicit yes before anything else.

## 2. Brainstorm — superpowers:brainstorming

Invoke the `superpowers:brainstorming` skill and follow it. Under this skill it works like this:

1. **Look before you ask.** Explore the repo first: locate the files and symbols the change would touch, read the current behavior, read AGENTS.md at the repo root (its guardrails bind the Context and the acceptance criteria). Never invent file paths, symbol names, or current behavior — every concrete reference must come from something you actually saw. Never ask what the repo already answers.
2. **Clarifying questions, one at a time.** Ask only what the request and the repo leave open, and only when the answer would change what gets built. Each question is its own message and always offers several concrete options with exactly one recommended, plus a one-line reason for the recommendation. This deliberately overrides brainstorming's default of open-ended questions with no options attached — under this skill, every clarifying question comes with options and a recommendation.
3. **The goal of the phase is three deliverables**, agreed with the user: the **scope** (what changes, what does not), the **acceptance criteria** (each independently verifiable), and the **testing strategy** (how the criteria will be proven). Keep asking until all three are defined.
4. **Lay out the approaches** before writing anything up, per brainstorming: the real alternatives, what each trades off, one recommended.
5. **Decision records.** Draft a record during the brainstorm ONLY when a qualifying architecture decision is resolved (a decision that changes the app's architecture, domain data flow, screen wiring, or CI pipeline design); every other decision is captured by the issue text alone and never becomes an ADR. A record is drafted per the `docs/spec/README.md` template and embedded with its full content in the issue's Context as a fenced block naming the target `docs/spec/NNNN-<slug>.md` path. Numbering: next = highest existing + 1.

## 3. Write the spec

When the questions are answered and the user has picked an approach, write the design doc — the spec — per brainstorming's Size the Work: a short design for a small change, the full written design for a project. It captures the intent and why, the scope (goals, non-goals, out of scope), the chosen approach and the alternatives considered, the acceptance criteria, and the testing strategy.

- Save it to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. In this repo `docs/superpowers/` is gitignored — the spec is a local working doc; do not commit it.
- **Hard gate: nothing gets implemented and no issue is filed until the user approves the spec.**
- Hand-off override: when running under this skill, brainstorming's step after the approved spec is §4 below, NOT the `writing-plans` skill — the executor writes the implementation plan itself from the issue.

## 4. Decide task boundaries

- One coherent change → exactly one issue.
- Split into multiple issues only when the approved spec clearly contains independent changes (e.g. an unrelated bugfix plus a feature). Each issue must be executable and verifiable on its own.
- File base tasks first, then reference the real issue number in dependents ("Depends on #14").
- If in doubt, one issue: a too-big issue is easier for an executor to handle than a wrongly split one.
- Before filing, check open issues for duplicates: `gh issue list --label task --state open`.

## 5. Compose the issue body

Use exactly this structure — same six sections, same order, no added or renamed sections, no decorations. Every section is always present; if a section has no content, write `None identified yet.`

```markdown
## Description
<Short description of the task/issue.>

## User story
As a <role>, I want <action/goal>, so that <benefit/value>.

## Context
<What is changing and how it will be implemented.>

## Acceptance criteria
- [ ] <criterion>
- [ ] <criterion>

## Testing strategy
<How the acceptance criteria will be proven.>

## Out Of scope
- <excluded work>
```

Section rules:

- **Description** — short description of the task: 1–2 sentences, what changes and why. Concrete, no filler ("This issue will…"), no restating the title.
- **User story** — one sentence, exactly in the template form above. Pick the persona that matches the benefit (the app's end user, a developer, a maintainer).
- **Context** — the section the executor reads first; make it self-sufficient. State the approach, name the real files (repo-relative paths) and symbols to touch, summarize the current behavior, and list constraints that bind the executor (conventions, dependencies, related issues). Explain the why behind non-obvious choices. Do not paste implementation code — describe the change instead. When a spec was written, reference its path for background ("Design doc: docs/superpowers/specs/…") — the issue must still stand alone without it. When a decision record was drafted during the brainstorm, embed it here as a fenced block naming its target `docs/spec/` path — it is not a separate issue section.
- **Acceptance criteria** — 3–7 checkbox items. Each must be independently verifiable by an executor without this conversation: observable behavior, measurable output, or a command and its expected result. Ban vague wording ("works well", "looks nice"). When the task touches code, include the repo's verification gate as an item — in this repo (per AGENTS.md): `flutter analyze` reports 0 issues and `flutter test` passes.
- **Testing strategy** — how the executor proves the acceptance criteria: the tests to add (kind — unit, widget, integration — where they live, and what each asserts, described rather than coded), the commands to run with their expected results, and any manual or UX verification steps. Ground it in the repo's real test setup; in this repo (per AGENTS.md): `test/` for unit and widget tests, `integration_test/smoke_test.dart` for the full-loop smoke test, and the gate `flutter analyze` (0 issues) + `flutter test` (all pass) that every code task runs. Purely non-code tasks (docs, skills, tooling configs) state how the change is verified without the Flutter gate.
- **Out Of scope** — related work deliberately excluded, so the executor doesn't scope-creep. Name it even when it's tempting ("the redesign of the cards themselves", "other screens with the same pattern").

Title: a concise imperative summary of the change ("Show candidate counts in row margins"). No prefix, no issue number, no trailing period.

## 6. File the issue

Run from the repo root so `gh` resolves the repo from the git remote:

```bash
# Fail fast if no repo is resolvable — do not guess a repo.
gh repo view --json nameWithOwner -q .nameWithOwner

# Ensure the label executors query on exists (idempotent).
gh label create task --color 1D76DB 2>/dev/null || true

# Write the composed body to a temp file, then file the issue.
gh issue create --title "<title>" --body-file /tmp/task-body.md --label task
```

- Always pass the body via `--body-file`, never inline — shell quoting mangles multi-line markdown.
- `gh issue create` prints the issue URL — report it back verbatim.
- If `gh repo view` fails (no remote, not authenticated), stop and tell the user what's missing instead of choosing a repo yourself.
- For multiple issues: file them one at a time (dependents need real numbers) and report every URL.

## Example

Illustrative — paths and details differ per task.

```markdown
## Description
The case-select screen leaves a large empty band below the card grid on wide viewports because the grid is top-aligned in a fixed-height container.

## User story
As a player, I want the case-select screen to fill the viewport, so that the layout doesn't look unfinished on desktop.

## Context
Presentation-only change in the case-select page widget. Replace the fixed-height wrapper with a `LayoutBuilder` + `Expanded` so the grid fills the available height, and cap card height so cards don't stretch on very tall screens. No game-logic changes. Follow-up from the UX review. Design doc: docs/superpowers/specs/2026-11-21-case-select-layout-design.md.

## Acceptance criteria
- [ ] At 1920×1080 in the web preview, no empty band remains below the grid
- [ ] Cards keep their designed height at 2560×1440 (no stretching)
- [ ] `flutter analyze` reports 0 issues and `flutter test` passes

## Testing strategy
- Add a widget test for the case-select page that pumps the screen at 1920×1080 and at 2560×1440 and asserts the grid fills the available height with no overflow and no card stretching.
- Run the full gate: `flutter analyze` reports 0 issues and `flutter test` passes.
- Manual UX pass in the web preview at both viewports: no empty band below the grid, cards at their designed height.

## Out Of scope
- Redesigning the cards themselves (tracked as a separate task)
- Applying the same fix to the in-game board layout
```
