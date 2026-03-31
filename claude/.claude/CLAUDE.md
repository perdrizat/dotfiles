# Global Claude Instructions

## WORKLOG Convention

Every project should have a `WORKLOG.md` in its root. This is the session diary.

**At the start of each session:** Read `WORKLOG.md` to understand recent context — what was investigated, changed, decided, and why.

**At the end of each session (or when asked to commit):** Append an entry:

```
## YYYY-MM-DD

**What changed:**
- Bullet list of concrete changes (files modified, features added, bugs fixed)

**Decisions & rationale:**
- Why we chose approach X over Y
- Trade-offs accepted

**Open threads:**
- What's unfinished or needs follow-up
```

If `WORKLOG.md` or `CLAUDE.md` don't exist in a project, suggest creating them.

## Memory Usage

Use auto-memory to persist context between sessions:
- **user**: Role, expertise, preferences that shape how to collaborate
- **feedback**: Corrections and confirmed approaches — what to repeat or avoid
- **project**: Active goals, deadlines, decisions not in code or git
- **reference**: Pointers to external systems (Linear, Slack, dashboards)

Don't save things derivable from code, git history, or existing docs.

## General Preferences

- Be concise. Lead with the answer, not the reasoning.
- Don't add features, refactor code, or make improvements beyond what was asked.
- When unsure about scope or approach, ask rather than guess.
