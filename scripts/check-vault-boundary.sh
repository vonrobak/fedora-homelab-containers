#!/bin/bash
# Vault-boundary backstop (knowledge-vault migration, 2026-07-13).
#
# The primary boundary is physical: internal docs live in the Huldr vault and
# reach this repo only through gitignored symlinks, so `git add` cannot stage
# them. This check is the configuration backstop behind that physics: reject
# any staged markdown whose frontmatter declares it internal, no matter how it
# got staged (copied out of the vault, symlink replaced by a real dir, ...).
#
# Exit 0 = clean, exit 1 = at least one staged file is marked internal/secret
# or references a vault directory by path (ADR-043 link policy / ADR-048).

set -euo pipefail

FAILED=0

while IFS= read -r file; do
    [[ "$file" == *.md ]] || continue
    # Read the staged blob, not the worktree file
    staged=$(git show ":$file" 2>/dev/null) || continue
    if head -30 <<<"$staged" \
        | grep -qE '^sensitivity:[[:space:]]*(internal|secret)[[:space:]]*$'; then
        echo "  ✗ $file is marked 'sensitivity: internal|secret' — belongs in the Huldr vault, not the public repo"
        FAILED=1
    fi
    # Vault dirs must not be referenced by path in public docs — drop the
    # reference or mention the doc by name only (ADR-043 D5). Files that must
    # show such a path (boundary docs, faithful code listings) opt out with an
    # <!-- allow-vault-paths --> comment anywhere in the file.
    if ! grep -q 'allow-vault-paths' <<<"$staged" \
        && grep -qE '9[0-9]-(archive|project-supervisor|plans|journals|reports)/' <<<"$staged"; then
        echo "  ✗ $file references a private vault directory by path (docs/9x) — drop it or use a name-only mention; add <!-- allow-vault-paths --> only if the path is inside a boundary doc or faithful code listing"
        FAILED=1
    fi
done < <(git diff --cached --name-only --diff-filter=ACM)

exit $FAILED
