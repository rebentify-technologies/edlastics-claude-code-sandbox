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
- Default: `model: "opus"` for any agent that writes code. Do **not** use `isolation: "worktree"` — use npm workspace worktrees instead (see below).

### Git Worktrees (npm workspaces pattern)
- **All changes in git worktrees** — never commit on a repo's checked-out branch. Applies to `/workspace` and `/workspace/git/*`.
- Use **npm workspaces** so all worktrees share a single `node_modules` — no per-worktree `npm install`.
- Repo structure:
  ```
  repo/
    node_modules/          # shared by all worktrees
    worktrees/
      <product>-local/     # persistent human-driven local-dev worktree (preserved by /clean-workspace)
      wt-main/             # git worktree for main branch
      wt-feature-xyz/      # git worktree for feature branch
    package.json           # "workspaces": ["worktrees/*"]
    .gitignore             # includes: worktrees/
  ```
- **Creating an ephemeral/agent worktree:** `git worktree add worktrees/wt-<name> <branch>` — the `wt-` prefix marks it as ephemeral so cleanup automation can target it positively.
- **`<product>-local` worktrees are off-limits to agents.** Every repo has a persistent `worktrees/<product>-local/` worktree (e.g., `elastic-pass-local`, `elastic-class-local`, `ui-common-local`) that belongs to the developer's IDE (Cursor). The absence of the `wt-` prefix is what marks it persistent. Agents never `cd` into it, build in it, run tests in it, or remove it. `/clean-workspace` preserves it under all circumstances. See `git/ai-knowledgebase/conventions/worktree-setup.md` for the full repo→name mapping.
- **Root `package.json`:** Only contains `"workspaces": ["worktrees/*"]`. Run `npm install` once from the root to resolve all dependencies.
- **Adding a dependency for a worktree:** `npm install <package> -w worktrees/wt-<name>` from the root.
- **`.gitignore`:** Add `worktrees/wt-*` to prevent worktree directories from being tracked.
- Agents should `cd` into their worktree directory (e.g., `worktrees/wt-feature-xyz/`) and work normally — `node_modules` resolves from the root.

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
