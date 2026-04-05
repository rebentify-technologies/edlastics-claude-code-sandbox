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

## Dev Container

The devcontainer uses a strict network firewall (`init-firewall.sh`) that only allows connections to: GitHub, npm registry, Anthropic API, Sentry, Statsig, VS Code marketplace, Atlassian API, and Slack webhooks. All other outbound traffic is rejected.
