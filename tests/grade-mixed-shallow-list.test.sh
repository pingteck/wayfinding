#!/usr/bin/env bash
# Regression test for grade-mixed-index.sh's --no-shallow-list flag (D2-negative / the
# D2-cap "dropped to pure delegation" case) and the ordinary shallow-list name-checking it's
# an alternative to. Before this test existed, --no-shallow-list was implemented in
# grade-mixed-index.sh but no committed fixture or recorded run ever invoked it, so it was
# gradeable but never graded. Never invokes git; every fixture is derived at runtime into a
# mktemp dir — this never edits tests/expected-*.md or anything under tests/fixtures/.
#
# Cases:
#   (a) pure-delegation parent (Shallow list: clause stripped) -> PASSES with --no-shallow-list
#   (b) the unmodified oracle (which HAS a list)                -> FAILS with --no-shallow-list
#   (c) a shallow list naming a non-component                   -> FAILS without the flag
#   (d) a shallow list omitting a real component                -> FAILS without the flag
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GRADER="$HERE/grade-mixed-index.sh"
ORACLE_PARENT="$HERE/expected-mixed-index.md"
ORACLE_MEMBER="$HERE/expected-mixed-web-monorepo.index.md"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail=0

# grade-mixed-index.sh resolves the member index as <MEMDIR>/web-monorepo.index.md; the
# member set/role/edge/marker checks are unaffected by anything below, so one staged member
# dir is reused for every case.
MEMDIR="$TMP/mem"
mkdir -p "$MEMDIR"
cp "$ORACLE_MEMBER" "$MEMDIR/web-monorepo.index.md"

# --- derive a pure-delegation parent: strip the WHOLE "Shallow list: ..." clause from the
# oracle's "## web-monorepo" Components: field. The clause wraps across two lines in the
# oracle ("...ends here. Shallow list: `web` (application)," / "  `admin` (application), `ui`
# (shared library)."), so this removes from the "Shallow list:" marker through the end of the
# wrapped list (up to the field's closing "- **" bullet) -- not just the marker word, which
# would leave a truncated, syntactically-broken list behind instead of pure delegation prose.
strip_shallow_list() {
  awk '
    /^## / {
      insec = ($0 ~ /^## web-monorepo[[:space:]]*$/) ? 1 : 0
      incomp=0; swallow=0
      print; next
    }
    insec && /^- \*\*Components:\*\*/ { incomp=1; swallow=0; print; next }
    insec && incomp && /^- \*\*/ { incomp=0; swallow=0; print; next }
    insec && incomp {
      line=$0
      if (!swallow && line ~ /Shallow list:/) {
        sub(/[[:space:]]*Shallow list:.*/, "", line)
        print line
        swallow=1
        next
      }
      if (swallow) { next }
      print; next
    }
    { print }
  ' "$1"
}

PURE="$TMP/pure-delegation.md"
strip_shallow_list "$ORACLE_PARENT" > "$PURE"

# sanity on the derivation itself, so a silently-broken awk pattern (e.g. the oracle's
# wording drifting) fails loudly here instead of the cases below passing/failing for the
# wrong reason.
grep -q 'Shallow list:' "$PURE" && { echo "FAIL: derivation did not strip the Shallow list: clause"; fail=1; }
grep -q 'this member owns' "$PURE" || { echo "FAIL: derivation over-stripped -- boundary prose is gone too"; fail=1; }

# --- (a) pure-delegation parent PASSES with --no-shallow-list ---
# NOTE: MEMBER ($3) is a positional arg read unconditionally before the trailing-args loop
# that recognizes --no-shallow-list, so it must be passed explicitly here -- otherwise
# "--no-shallow-list" itself gets consumed as MEMBER instead of being recognized as a flag.
out_a="$(bash "$GRADER" "$PURE" "$MEMDIR" web-monorepo --no-shallow-list 2>&1)"; rc_a=$?
{ [ "$rc_a" = "0" ] && printf '%s\n' "$out_a" | grep -q '^MIXED INDEX OK$'; } \
  || { echo "FAIL (a) pure-delegation + --no-shallow-list: expected MIXED INDEX OK (rc=$rc_a):"; printf '%s\n' "$out_a"; fail=1; }

# --- (b) the unmodified oracle (HAS a list) FAILS with --no-shallow-list ---
out_b="$(bash "$GRADER" "$ORACLE_PARENT" "$MEMDIR" web-monorepo --no-shallow-list 2>&1)"; rc_b=$?
{ [ "$rc_b" != "0" ] && printf '%s\n' "$out_b" | grep -q '^MIXED INDEX FAILED$'; } \
  || { echo "FAIL (b) oracle + --no-shallow-list: expected MIXED INDEX FAILED (rc=$rc_b):"; printf '%s\n' "$out_b"; fail=1; }

# --- (c) a shallow list naming a non-component FAILS without the flag ---
BADNAME="$TMP/badname.md"
sed 's/`ui` (shared library)/`uix` (shared library)/' "$ORACLE_PARENT" > "$BADNAME"
grep -q '`uix`' "$BADNAME" || { echo "FAIL: badname derivation did not take"; fail=1; }
out_c="$(bash "$GRADER" "$BADNAME" "$MEMDIR" 2>&1)"; rc_c=$?
{ [ "$rc_c" != "0" ] && printf '%s\n' "$out_c" | grep -q 'not a component'; } \
  || { echo "FAIL (c) non-component name: expected a 'not a component' MISS + non-zero exit (rc=$rc_c):"; printf '%s\n' "$out_c"; fail=1; }

# --- (d) a shallow list omitting a real component FAILS without the flag ---
OMIT="$TMP/omit.md"
sed 's/`admin` (application), `ui` (shared library)\./`admin` (application)./' "$ORACLE_PARENT" > "$OMIT"
grep -q '`ui` (shared library)' "$OMIT" && { echo "FAIL: omit derivation did not take"; fail=1; }
out_d="$(bash "$GRADER" "$OMIT" "$MEMDIR" 2>&1)"; rc_d=$?
{ [ "$rc_d" != "0" ] && printf '%s\n' "$out_d" | grep -q 'omits `ui`'; } \
  || { echo "FAIL (d) omitted component: expected 'omits \`ui\`' MISS + non-zero exit (rc=$rc_d):"; printf '%s\n' "$out_d"; fail=1; }

[ "$fail" = "0" ] && echo "MIXED SHALLOW-LIST REGRESSION OK" || echo "MIXED SHALLOW-LIST REGRESSION FAILED"
exit $fail
