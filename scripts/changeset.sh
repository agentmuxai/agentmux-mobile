#!/usr/bin/env bash
# changeset.sh — add a changeset for this PR (see .changesets/README.md).
#
# Usage:
#   scripts/changeset.sh <patch|minor|major> "<one-line summary>"
#
# Writes .changesets/<unix-ts>-<slug>-<rand4>.md with the type in its front
# matter and the summary as its body, and prints the path. Commit that file
# with the change.

set -euo pipefail

TYPE="${1:-}"
DESC="${2:-}"

if [[ -z "$TYPE" || -z "$DESC" ]]; then
    echo "Usage: $0 <patch|minor|major> \"<one-line summary>\"" >&2
    exit 1
fi

case "$TYPE" in
    patch|minor|major) ;;
    *)
        echo "ERROR: type must be one of: patch | minor | major (got: $TYPE)" >&2
        exit 1
        ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
    echo "ERROR: not inside a git repository." >&2
    exit 1
fi

DIR="$REPO_ROOT/.changesets"
mkdir -p "$DIR"

# Slug: lowercase, anything non-alphanumeric becomes `-`, trimmed, at most 60
# characters. The random suffix keeps two runs in the same second with the same
# summary from writing the same file.
TS="$(date +%s)"
SLUG="$(printf '%s' "$DESC" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-60)"
[[ -z "$SLUG" ]] && SLUG="change"
RAND="$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 4)"

FILE="$DIR/${TS}-${SLUG}-${RAND}.md"

cat >"$FILE" <<EOF
---
type: $TYPE
---

$DESC
EOF

echo "Wrote $FILE" >&2
echo "$FILE"
