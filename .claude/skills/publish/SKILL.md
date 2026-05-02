---
name: publish
description: Bump plugin version(s), commit, and push to publish changes to the marketplace.
---

You are publishing updated plugin(s) to the marketplace. This means bumping version numbers, committing, and pushing. Include whatever changes are in the working dir currently in your commit.

## Steps

1. **Determine which plugins changed.** `git status` and `git diff` against the last commit will tell you. Only bump versions for plugins with actual changes — don't bump untouched plugins.

2. **Determine the version bump per changed plugin.** Patch / minor / major. Use semver (e.g., 0.1.0 → 0.1.1 for patch, 0.2.0 for minor, 1.0.0 for major). Ask the user if uncertain.

3. **Read current versions** from both files for each changed plugin:
   - `.claude-plugin/marketplace.json` (the `version` field inside each plugin's entry)
   - `plugins/<plugin-name>/.claude-plugin/plugin.json` (the top-level `version` field)

4. **Bump both version fields** to the new version. Both must match.

5. **Commit and push.** If no changes other than version bumps: `Bump <plugin> to X.Y.Z` (or list each plugin if multiple). Then push to the remote.
