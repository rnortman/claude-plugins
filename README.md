# claude-plugins

A Claude Code plugin marketplace with two plugins for opinionated, review-driven engineering workflows.

## Plugins

- **[review-chain](plugins/review-chain/)** — Orchestrator-driven workflow with adversarial review chains. Specialist reviewers (slop, scope, security, correctness, error-handling, tests, reuse, quality, efficiency) run in parallel against each commit; a responder fact-checks every finding; a judge adjudicates. All agents are one-shot, file-based, and token-frugal — the orchestrator consumes only short summaries and paths.
- **[setup-project](plugins/setup-project/)** — Optional bootstrap that wires the orchestrator as the default agent, adds a generic Working-With-Claude-Code section to `CLAUDE.md`, and installs a `TODO.md` + `TODO(slug)` tracking convention. Take it or leave it — `review-chain` works without it.

## Install

```bash
# Add the marketplace (one-time, user-wide across all projects by default)
claude plugin marketplace add https://github.com/rnortman/claude-plugins.git

# Or add at project scope (shared with teammates via .claude/settings.json)
claude plugin marketplace add https://github.com/rnortman/claude-plugins.git --scope project

# Install the plugin(s)
claude plugin install review-chain@rnortman-plugins
claude plugin install setup-project@rnortman-plugins   # optional
```

Or test locally without installing into the marketplace:

```bash
claude --plugin-dir ./plugins/review-chain
```

## License

MIT — see [LICENSE](LICENSE).
