# Changesets

Every PR adds one **changeset**: a small file in this directory saying what the
PR changes, for the changelog. One file per PR, with a unique name, so PRs never
conflict over a shared changelog file.

```bash
scripts/changeset.sh patch "fix(nav): the docs link opens the right page"
```

writes `.changesets/<unix-ts>-<slug>-<rand4>.md`:

```markdown
---
type: patch
---

fix(nav): the docs link opens the right page
```

Commit it with the change. `type` is `patch`, `minor` or `major`; write the
description for a reader of the changelog, not for the reviewer.

## Enforced by CI

The `changeset` check (`.github/workflows/changeset.yml`) fails a PR that adds
no changeset, or whose changeset has no valid `type:` or no description. A PR
that genuinely needs no entry (a CI tweak, a typo fix nobody would look for in a
changelog) gets the `no-changeset` label instead; adding the label re-runs the
check. Dependabot and Renovate PRs are exempt.

The same convention and check are used in `agentmuxai/agentmux`, where a release
step folds the changesets into the version history.
