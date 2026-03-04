#!/usr/bin/env bash
# Scan tracked files for likely committed secrets.
# Run before commit; add to pre-commit or CI.
# See documents/SECURITY.md.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

# Ensure .env is not tracked
if git ls-files --error-unmatch .env 2>/dev/null; then
  echo "ERROR: .env is tracked by git. Add it to .gitignore and remove from index."
  FAIL=1
fi

# Patterns that likely indicate committed secrets (exclude .env.example and docs)
EXCLUDE='\.env\.example|SECURITY\.md|documents/|README|QUICKSTART|AGENTS\.md|check_secrets\.sh'
FILES="$(git ls-files 2>/dev/null | grep -vE "($EXCLUDE)" || true)"

if [ -n "$FILES" ]; then
  # OpenAI-style key
  if echo "$FILES" | xargs grep -lE 'sk-[a-zA-Z0-9]{20,}' 2>/dev/null; then
    echo "ERROR: Possible OpenAI API key (sk-...) found in tracked files."
    FAIL=1
  fi

  # MongoDB URI with password
  if echo "$FILES" | xargs grep -lE 'mongodb\+srv://[^:]+:[^@]+@' 2>/dev/null; then
    echo "ERROR: Possible MongoDB URI with password found in tracked files."
    FAIL=1
  fi
fi

if [ $FAIL -eq 1 ]; then
  echo "Fix the issues above before committing. See documents/SECURITY.md."
  exit 1
fi

echo "check_secrets: no obvious secrets found in tracked files."
exit 0
