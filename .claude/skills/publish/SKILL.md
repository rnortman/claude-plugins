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

5. **Update `CHANGELOG.md`** (repo root). Add a `### X.Y.Z — YYYY-MM-DD` entry under the appropriate plugin section, with a short summary line and a bullet list of notable changes. Describe only what's actually in the diff since the prior release — don't fabricate. Skip plugins with no changes. If `CHANGELOG.md` doesn't exist yet, create it with a section per plugin and a retroactive entry for the prior release.

6. **Commit and push.** If no changes other than version bumps + changelog: `Bump <plugin> to X.Y.Z` (or list each plugin if multiple). Otherwise lead with the bump and append a brief description of the user-visible change. Then push to the remote.
