#!/usr/bin/env bash
# Mutation tests for tests/grade-multirepo-index.sh — i.e. a test that the GRADER CAN FAIL.
#
# WHY THIS EXISTS. `grade-multirepo-index.sh` grades output an agent produced, so it only ever
# runs after a dogfood run and a green result is easy to mistake for evidence. Four measurement
# failures on this project in one session (a vacuous test, a corpus tool more permissive than
# the tool it measured, a grader that couldn't see what it was asked to, a gate that flagged its
# own safety comment) all had the same shape: nobody checked the instrument could go red.
#
# So: take the hand-authored oracle — which MUST pass — mutate it one defect at a time, and
# assert the grader rejects each. Every mutation below corresponds to a real defect class the
# grader claims to catch. M8 is the important one: it is the whole-file-grep trap, where an
# assertion passes because the token exists SOMEWHERE rather than in the right section.
#
# This is a mechanical gate — no agent needed — so it runs in tests/run-all.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GRADER="$HERE/grade-multirepo-index.sh"
ORACLE="$HERE/expected-layer2-chain-index.md"
SPEC=(redirect-svc='Chi|pgx' agents-only-svc='BoltDB' readme-only-svc='zerolog'
      --unprofiled redirect-svc,agents-only-svc,readme-only-svc)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0

grade() { bash "$GRADER" "$1" "${SPEC[@]}" >/dev/null 2>&1; }

# expect_pass <file> <label>
expect_pass() {
  if grade "$1"; then printf '  PASS  %s\n' "$2"
  else printf '  FAIL  %s (grader rejected a VALID index)\n' "$2"
     bash "$GRADER" "$1" "${SPEC[@]}" 2>&1 | sed 's/^/          /'; fail=1; fi
}
# expect_red <label> <mutation-cmd applied to $TMP/idx.md>
#
# The `cmp` guard is not decoration. On the first run of this file, M2 used sed's `0,/re/`
# address and M10 used `,+1` — both GNU extensions. BSD sed (macOS) accepts them, exits 0, and
# edits NOTHING. M2 therefore "failed to go red" against a perfectly good grader, and M10 went
# red for a reason other than the one it claimed. A mutation that does not mutate is a test
# that cannot fail, so assert the file actually changed BEFORE trusting either colour.
expect_red() {
  local label="$1"; shift
  cp "$ORACLE" "$TMP/idx.md"
  "$@"
  if cmp -s "$ORACLE" "$TMP/idx.md"; then
    printf '  FAIL  %s — MUTATION IS A NO-OP (the test, not the grader, is broken)\n' "$label"
    fail=1; return
  fi
  if grade "$TMP/idx.md"; then
    printf '  FAIL  %s — grader stayed GREEN on a broken index\n' "$label"; fail=1
  else printf '  PASS  %s\n' "$label"; fi
}

# --- mutations, each a one-line edit to $TMP/idx.md -------------------------------------
# Portable in-place edit. `sed -i ''` is BSD-only: GNU sed (Linux, CI) reads the '' as the
# script or a filename, and the mutation silently does nothing — caught by the cmp no-op guard
# above when this suite first ran on Ubuntu (2026-10-14). Write to a temp file and move instead.
sedi() { sed "$@" "$TMP/idx.md" > "$TMP/t" && mv "$TMP/t" "$TMP/idx.md"; }
m_drop_section()   { awk '/^## readme-only-svc/{s=1} /^## /&&!/readme-only-svc/{s=0} !s' "$TMP/idx.md" > "$TMP/t" && mv "$TMP/t" "$TMP/idx.md"; }
m_drop_purpose()   { awk '!d && /^- \*\*Purpose:\*\*/ {sub(/^- \*\*Purpose:\*\* */,"  "); d=1} 1' "$TMP/idx.md" > "$TMP/t" && mv "$TMP/t" "$TMP/idx.md"; }
m_drop_xrepo()     { sedi 's/^- \*\*Cross-repo links:\*\* Publishes to/- **Notes:** Publishes to/'; }
m_one_sided()      { sedi 's/exposes an HTTP API that `readme-only-svc` scrapes/exposes an HTTP API/'; }
m_stack_generic()  { sedi 's/Go 1.25, embedded BoltDB./Go, an embedded key-value store./'; }
m_phantom_repo()   { printf '\n## phantom-svc\n\n- **Purpose:** Invented.\n- **Role:** Invented.\n- **Entry points:** Invented.\n- **Cross-repo links:** None.\n- **Stack:** Go.\n' >> "$TMP/idx.md"; }
m_no_edges()       { sedi -e 's/`agents-only-svc`/the downstream service/g' -e 's/`readme-only-svc`/the exporter/g' -e 's/`redirect-svc`/the ingest service/g'; }
m_stack_wrong_sec(){ sedi -e 's/Go 1.25, embedded BoltDB./Go 1.25, an embedded store./' \
                                -e 's/Go 1.25, zerolog for structured output/Go 1.25, BoltDB and zerolog for structured output/'; }
m_drop_marker()    { awk '!d && /Layer-4 baseline only/ {d=1; next} 1' "$TMP/idx.md" > "$TMP/t" && mv "$TMP/t" "$TMP/idx.md"; }
m_drop_h1()        { sedi '1s/^# /XX /'; }
m_drop_summary()   { awk '!/^> /' "$TMP/idx.md" > "$TMP/t" && mv "$TMP/t" "$TMP/idx.md"; }

echo "grade-multirepo-index.sh — can it fail?"
expect_pass "$ORACLE" "the hand-authored oracle PASSES (control)"
expect_red "M1 missing repo section"              m_drop_section
expect_red "M2 missing Purpose field"             m_drop_purpose
expect_red "M3 missing Cross-repo links field"    m_drop_xrepo
expect_red "M4 one-sided cross-repo edge"         m_one_sided
expect_red "M5 stack fact replaced by generic"    m_stack_generic
expect_red "M6 hallucinated extra repo"           m_phantom_repo
expect_red "M7 zero edges (reciprocity vacuous)"  m_no_edges
expect_red "M8 stack token in the WRONG section"  m_stack_wrong_sec
expect_red "M9 missing H1"                        m_drop_h1
expect_red "M10 missing blockquote summary"       m_drop_summary
expect_red "M11 unprofiled repo lost its marker"  m_drop_marker

# M12 — the OTHER direction of marker selectivity. The layer2-chain fixture is all-Go and every
# repo is unprofiled, so it cannot supply a profiled repo to test the false-positive direction
# against. Test the GRADER instead: declare redirect-svc profiled while the (unmutated) oracle
# still carries its marker. A grader that only checks "marker present" stays green; one that
# checks selectivity goes red.
#
# NOTE the spec is written out longhand rather than reusing $SPEC + --profiled. Appending
# --profiled to a SPEC that already lists redirect-svc as --unprofiled puts it in BOTH lists,
# and the grader's if/elif then let unprofiled win — so the check passed while never reaching
# the branch it claimed to test. The grader now rejects that spec outright (exit 2); this is
# the invocation that actually exercises the profiled branch.
printf '  '
if bash "$GRADER" "$ORACLE" redirect-svc='Chi|pgx' agents-only-svc='BoltDB' readme-only-svc='zerolog' \
     --unprofiled agents-only-svc,readme-only-svc --profiled redirect-svc >/dev/null 2>&1; then
  printf 'FAIL  M12 marker present on a repo declared PROFILED — grader stayed GREEN\n'; fail=1
else printf 'PASS  M12 marker present on a repo declared PROFILED\n'; fi

# M13 — the contradictory spec itself must be rejected, not silently resolved.
printf '  '
bash "$GRADER" "$ORACLE" "${SPEC[@]}" --profiled redirect-svc >/dev/null 2>&1
if [ $? = 2 ]; then printf 'PASS  M13 repo in both --profiled and --unprofiled is a spec error\n'
else printf 'FAIL  M13 contradictory spec was silently accepted\n'; fail=1; fi

echo
[ "$fail" = 0 ] && echo "GRADER MUTATION OK" || echo "GRADER MUTATION FAILED"
exit $fail
