#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../scripts/check-doc-paths.sh"
fail=0
run() { bash "$SCRIPT" "$1" >/dev/null 2>&1; echo $?; }

# good.md references an existing file -> exit 0
[ "$(run "$DIR/fixtures/good")" = "0" ] || { echo "FAIL good"; fail=1; }
# dead-path.md references a missing file -> exit non-zero
[ "$(run "$DIR/fixtures/dead")" != "0" ] || { echo "FAIL dead"; fail=1; }
# placeholders.md has URLs, ~-paths, /UPPER/PLACEHOLDER/, fenced code -> exit 0 (no false positives)
[ "$(run "$DIR/fixtures/placeholders")" = "0" ] || { echo "FAIL placeholders"; fail=1; }
# sibling.md references ABSENT ledger-api/ + ledger-web/ paths -> skipped WITH A NOTE, exit 0 (F6).
# Assert both the exit code AND the note text, so this proves the skip-with-note branch fired
# (remove that branch and these become MISSING -> exit 1 -> this case fails).
ST="$(mktemp -d)"   # sibling fixtures carry .member-repo markers; staging turns them into .git
bash "$DIR/stage-fixture.sh" "$DIR/fixtures/sibling" "$ST/sibling"
bash "$DIR/stage-fixture.sh" "$DIR/fixtures/sibling-generic" "$ST/sibling-generic"
SIB_OUT="$(bash "$SCRIPT" "$ST/sibling" 2>&1)"; SIB_RC=$?
{ [ "$SIB_RC" = "0" ] && printf '%s\n' "$SIB_OUT" | grep -q "skipping sibling-repo ref"; } \
  || { echo "FAIL sibling (rc=$SIB_RC)"; fail=1; }
# sibling-generic/doc.md references an arbitrary present member repo (some-service/, marked
# by its own .git, no hardcoded name) -> skipped WITH A NOTE, exit 0. Proves the skip
# generalizes off the named sibling repos above to any present sibling member repo.
GEN_OUT="$(bash "$SCRIPT" "$ST/sibling-generic" 2>&1)"; GEN_RC=$?
{ [ "$GEN_RC" = "0" ] && printf '%s\n' "$GEN_OUT" | grep -q "skipping sibling-repo ref"; } \
  || { echo "FAIL sibling-generic (rc=$GEN_RC)"; fail=1; }
# --- a per-directory CLAUDE.md is NOT a sibling repo (2026-10-14) ---
# Monorepos carry per-directory CLAUDE.md files (getsentry/sentry: src/, static/, tests/). The
# guard used to treat a bare CLAUDE.md as a sibling-REPO marker and skip every link into that
# dir, so a dead link into `src/` went unreported. Only `.git` marks a member repo.
PD="$(mktemp -d)"
mkdir -p "$PD/src"
printf '# src conventions\n' > "$PD/src/CLAUDE.md"
printf '# Overview\n\nSee [the handler](src/handlers/missing.py).\n' > "$PD/README.md"
PD_OUT="$(bash "$SCRIPT" "$PD" 2>&1)"; PD_RC=$?
{ [ "$PD_RC" != "0" ] && printf '%s\n' "$PD_OUT" | grep -q "MISSING:.*src/handlers/missing.py"; } \
  || { echo "FAIL per-dir-claude-md: dead link into a dir with only a CLAUDE.md was not reported (rc=$PD_RC)"; fail=1; }
rm -rf "$PD" "$ST"
# --- delegation pointers are CHECKED, not skipped (R12) ---
DT="$(mktemp -d)"
mkdir -p "$DT/web-monorepo"
printf 'gitdir: /x/web-monorepo.git\n' > "$DT/web-monorepo/.git"   # a member REPO
printf '# Parent\n\n- **Components:** Delegates to [member index](web-monorepo/workspace-index.md) — boundary.\n' > "$DT/parent.md"
[ "$(run "$DT")" != "0" ] || { echo "FAIL: dangling in-place delegation pointer was not reported"; fail=1; }
printf '# member index\n' > "$DT/web-monorepo/workspace-index.md"
[ "$(run "$DT")" = "0" ] || { echo "FAIL: a delegation pointer that EXISTS was reported as missing"; fail=1; }
# an ordinary ref into a sibling member repo is still skipped (no over-correction)
printf '# Parent\n\nSee [details](web-monorepo/src/Whatever.java) for details.\n' > "$DT/parent.md"
[ "$(run "$DT")" = "0" ] || { echo "FAIL: sibling-skip over-corrected — ordinary member refs must stay skipped"; fail=1; }

[ "$fail" = "0" ] && echo "ALL PASS" || echo "SOME FAIL"
exit $fail
