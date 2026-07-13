#!/bin/bash
# Vault-boundary backstop (knowledge-vault migration, 2026-07-13).
#
# The primary boundary is physical: internal docs live in the Huldr vault and
# reach this repo only through gitignored symlinks, so `git add` cannot stage
# them. This check is the configuration backstop behind that physics: reject
# any staged markdown whose frontmatter declares it internal, no matter how it
# got staged (copied out of the vault, symlink replaced by a real dir, ...).
#
# Exit 0 = clean, exit 1 = at least one staged file is marked internal/secret.

set -euo pipefail

FAILED=0

while IFS= read -r file; do
    [[ "$file" == *.md ]] || continue
    # Read the staged blob, not the worktree file
    if git show ":$file" 2>/dev/null | head -30 \
        | grep -qE '^sensitivity:[[:space:]]*(internal|secret)[[:space:]]*$'; then
        echo "  ✗ $file is marked 'sensitivity: internal|secret' — belongs in the Huldr vault, not the public repo"
        FAILED=1
    fi
done < <(git diff --cached --name-only --diff-filter=ACM)

exit $FAILED
