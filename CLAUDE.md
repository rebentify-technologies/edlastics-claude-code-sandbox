# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the **edlastics-claude-code-sandbox** repository (rebentify-technologies/edlastics-claude-code-sandbox), forked from anthropics/claude-code. It contains:

- **plugins/**: Official Claude Code plugins (slash commands, agents, hooks, skills)
- **scripts/**: GitHub issue management automation (TypeScript/Bun scripts for duplicate detection, lifecycle management, sweeping stale issues)
- **examples/**: Example hooks and settings configurations
- **.github/workflows/**: CI workflows for issue triage, duplicate detection, and @claude integration
- **.devcontainer/**: Dev container setup with network firewall restricting outbound traffic to GitHub, npm, Anthropic APIs, and VS Code services

## Scripts

Scripts in `scripts/` are TypeScript files that run with **Bun** (not Node.js). They use `fetch` directly against the GitHub API and are invoked by GitHub Actions workflows.

## Plugin Structure

Each plugin in `plugins/` follows this structure:
```
plugin-name/
├── .claude-plugin/plugin.json   # Plugin metadata (name, description, version)
├── commands/                    # Slash command definitions (markdown files)
├── agents/                      # Agent definitions (markdown files)
├── skills/                      # Skill definitions (markdown files)
├── hooks/hooks.json             # Hook event handlers
└── README.md
```

Plugin commands, agents, and skills are defined as **markdown files with YAML frontmatter** — they are prompt-based, not code. Hook handlers can be shell scripts or Python.

## Workflow

### Planning
- **Enter plan mode for any non-trivial task** (3+ steps or architectural decisions). Use it for verification strategy too, not just building.
- If something goes sideways mid-implementation, **stop and re-plan immediately** — don't keep pushing a broken approach.

### Subagents
- Use subagents liberally — one focused task each. Offload research, exploration, and parallel analysis.
- For complex problems, throw more compute at it via parallel subagents.
- Default: `model: "opus"` for any agent that writes code. Do **not** use `isolation: "worktree"` — use the split layout below.

### Workspace layout
- **All changes in git worktrees** — never commit on a repo's checked-out branch. Applies to `/workspace` and `/workspace/git/*`.
- Every repo lives in two places:
  ```
  /workspace/
    git/<repo>/                    # canonical clone (agents work here in worktrees/wt-*)
      worktrees/
        wt-<feature>/              # ephemeral worktree for a feature/story
    local-dev/<repo>/              # the developer's IDE checkout (Cursor) on branch `local-dev`
  ```
- **`/workspace/local-dev/` is off-limits to agents.** Agents never `cd` into it, build in it, run tests in it, or remove it. `/clean-workspace` preserves it under all circumstances. The developer works there; agents work in `/workspace/git/<repo>/worktrees/wt-*/`.
- **Creating an ephemeral/agent worktree:** `git worktree add worktrees/wt-<name> <branch>` from the canonical clone. The `wt-` prefix marks it ephemeral so cleanup automation can target it positively.
- **Node package manager:** repos migrating to pnpm declare `"packageManager": "pnpm@<version>"` in `package.json` — Corepack downloads the matching version on first use. Repos not yet migrated still use npm. See [RS-2122](https://rebentify.atlassian.net/browse/RS-2122).
- **Per-worktree installs:** each worktree gets its own `node_modules`. With pnpm's content-addressable store, the extra disk + time cost is near zero after the first install.
- See `git/ai-knowledgebase/conventions/worktree-setup.md` for the full convention (Cursor setup, troubleshooting, GCP Artifact Registry auth).

### Verification
- **Never mark a task complete without proving it works.** Run builds, tests, check logs, and demonstrate correctness.
- Hold yourself to a staff engineer standard before presenting work.

### Bug Fixing
- When given a bug report, **just fix it**. Zero context switching required from the user. Point at logs, errors, and failing tests — then resolve them. Fix failing CI without being told how.

### Quality
- For non-trivial changes, pause and ask: *"Is there a more elegant way?"* If a fix feels hacky, step back and implement the clean solution. Skip for simple fixes.
- Find root causes. No temporary fixes. Minimal code impact — only touch what's necessary.

### Learnings
- After any correction, update the relevant doc in `/workspace/git/ai-knowledgebase/`. No local memory files — keep knowledge centralized.
- Review the relevant knowledgebase docs (`/workspace/git/ai-knowledgebase/repos/`, `/workspace/git/ai-knowledgebase/conventions/`) at the start of work in any repo.

## Dev Container

The devcontainer uses a strict network firewall (`init-firewall.sh`) that only allows connections to: GitHub, npm registry, Anthropic API, Sentry, Statsig, VS Code marketplace, Atlassian API, and Slack webhooks. All other outbound traffic is rejected.
