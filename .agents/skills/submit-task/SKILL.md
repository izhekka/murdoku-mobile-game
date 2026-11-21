---
name: submit-task
description: Analyze the application against the user's request, decide what should change, and file the work as deterministically structured GitHub issue(s) for executor agents. Use whenever the orchestrator is asked to submit, file, dispatch, or hand off work — "submit this as a task", "turn this into an issue", "break this down for the executors", "create the task(s)" — even when the user doesn't say "issue" or "task" explicitly.
---

# Submit Task

Turn a user request into executor-ready GitHub issues. Executors read these issues in isolation, with no access to this conversation — the issue must carry the full analysis. The output structure is deterministic: identical sections, identical order, on every issue.

## 1. Analyze before writing

1. Parse the user's request: what outcome do they want, for whom, and what constraints did they state?
2. Ground it in the code. Locate the files and symbols the change will touch and the current behavior by exploring the repo. Never invent file paths, symbol names, or current behavior — every concrete reference must come from something you actually saw.
3. If the repo root has AGENTS.md (or a similar conventions file), read it. Its guardrails constrain both the Context and the acceptance criteria.
4. If the request is ambiguous in a way that changes what gets built, ask the user first. Do not guess, and do not file a "please clarify" issue.

## 2. Decide task boundaries

- One coherent change → exactly one issue.
- Split into multiple issues only when the request clearly contains independent changes (e.g. an unrelated bugfix plus a feature). Each issue must be executable and verifiable on its own.
- File base tasks first, then reference the real issue number in dependents ("Depends on #14").
- If in doubt, one issue: a too-big issue is easier for an executor to handle than a wrongly split one.
- Before filing, check open issues for duplicates: `gh issue list --label task --state open`.

## 3. Compose the issue body

Use exactly this structure — same five sections, same order, no added or renamed sections, no decorations. Every section is always present; if a section has no content, write `None identified yet.`

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

## Out Of scope
- <excluded work>
```

Section rules:

- **Description** — short description of the task: 1–2 sentences, what changes and why. Concrete, no filler ("This issue will…"), no restating the title.
- **User story** — one sentence, exactly in the template form above. Pick the persona that matches the benefit (the app's end user, a developer, a maintainer).
- **Context** — the section the executor reads first; make it self-sufficient. State the approach, name the real files (repo-relative paths) and symbols to touch, summarize the current behavior, and list constraints that bind the executor (conventions, dependencies, related issues). Explain the why behind non-obvious choices. Do not paste implementation code — describe the change instead.
- **Acceptance criteria** — 3–7 checkbox items. Each must be independently verifiable by an executor without this conversation: observable behavior, measurable output, or a command and its expected result. Ban vague wording ("works well", "looks nice"). When the task touches code, include the repo's verification gate as an item — in this repo (per AGENTS.md): `flutter analyze` reports 0 issues and `flutter test` passes.
- **Out Of scope** — related work deliberately excluded, so the executor doesn't scope-creep. Name it even when it's tempting ("the redesign of the cards themselves", "other screens with the same pattern").

Title: a concise imperative summary of the change ("Show candidate counts in row margins"). No prefix, no issue number, no trailing period.

## 4. File the issue

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
Presentation-only change in the case-select page widget. Replace the fixed-height wrapper with a `LayoutBuilder` + `Expanded` so the grid fills the available height, and cap card height so cards don't stretch on very tall screens. No game-logic changes. Follow-up from the UX review.

## Acceptance criteria
- [ ] At 1920×1080 in the web preview, no empty band remains below the grid
- [ ] Cards keep their designed height at 2560×1440 (no stretching)
- [ ] `flutter analyze` reports 0 issues and `flutter test` passes

## Out Of scope
- Redesigning the cards themselves (tracked as a separate task)
- Applying the same fix to the in-game board layout
```
