#!/usr/bin/env bash
# Every mechanical gate, in one command. Run this before and after any change to
# scripts/detect-mode.sh, references/, or skills/.
#
# WHY THIS EXISTS: there are a dozen scripts under tests/ and only these are gates — the rest
# are graders invoked BY a gate, or helpers. Which is which was institutional knowledge until
# this file existed, and a session that doesn't know it will skip a gate silently.
#
# WHAT THIS DOES NOT COVER — read this before trusting a green run:
#   * Agent-graded checks. tests/grade-index.sh, grade-mixed-index.sh, grade-monorepo-index.sh,
#     grade-onboard-component.sh and grade-layer2-chain.sh all grade an index an AGENT produced;
#     they need a dogfood run first (see tests/dogfood.md). They are not run here.
#   * Anything about skill PROSE. Every gate below tests scripts/detect-mode.sh.
#   * A green run proves no regression against fixtures we already thought of. It is not
#     evidence a new design is correct: on 2026-07-27 the entire suite passed against a
#     faithful prototype of a design that demoted every Maven/Gradle/Python monorepo. Write the
#     failing fixture first.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1
fail=0
run() { # run <label> <cmd...>
  local label="$1"; shift
  printf '%-34s ' "$label"
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc = 0 ]; then printf '%s\n' "$(printf '%s' "$out" | tail -1)"
  else printf 'FAILED\n'; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; fi
}

echo "== detect-mode gates =="
for f in multirepo:multi-repo monorepo:monorepo mixed:mixed; do
  fx="${f%%:*}"; mode="${f##*:}"
  out="$(mktemp)"; ws="$(mktemp -d)"
  # staged: `.member-repo` markers become real `.git` files (see tests/stage-fixture.sh)
  bash tests/stage-fixture.sh "tests/fixtures/$fx" "$ws/$fx" && bash scripts/detect-mode.sh "$ws/$fx" > "$out" 2>&1
  run "frozen oracle: $fx" bash tests/grade-detect-mode.sh "$fx" "$out" "$mode"
  rm -rf "$out" "$ws"
done
run "declared-member set (F3/F4/F5)" bash tests/detect-mode-declared.test.sh
run "classification + veto (F2)"     bash tests/detect-mode-classify.test.sh
run "runtime safety (M3/H4/L1)"      bash tests/detect-mode-safety.test.sh

echo "== payload gates =="
run "doc paths"                      bash tests/check-doc-paths.test.sh
run "mixed shallow-list regression"  bash tests/grade-mixed-shallow-list.test.sh
run "multirepo grader can fail"      bash tests/grade-multirepo-index.test.sh
run "dogfood seeds + gate1 can fail"  bash tests/layer2-seeds.test.sh
run "skim/precedence graders can fail" bash tests/agent-checks.test.sh
run "bootstrap skill shape"          bash tests/skill-shape.test.sh

echo "== publishability =="
# WHAT SHIPS is computed, never assumed: every file `git add -A` would stage in the fresh
# `git init` planned for publish — tracked or untracked, minus whatever .gitignore matches.
# `git check-ignore --no-index` applies the ignore rules to TRACKED files too, so .gitignore
# is the single source of truth for the local-only set (see its
# publish-time block) and these gates give the same answer before and after the fresh init.
#
# Until 2026-10-14 the origin-detail gate scanned the FILESYSTEM with an `--exclude-dir`
# exemption for the historical specs, and the publish checklist said to delete that exemption
# after the fresh init. That could never pass: the local-only docs stay on local disk after the
# init (untracked, not deleted), so dropping the exemption re-scanned them and failed forever.
# Found by simulating the publish, not by reasoning about it.
SHIPPED="$( { git ls-files --cached; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u \
  | git check-ignore --no-index --stdin -v -n 2>/dev/null | awk -F'\t' '$1=="::"{print $2}' )"
nship="$(printf '%s\n' "$SHIPPED" | /usr/bin/grep -c .)"
# Both gates below are judged by OUTPUT, never by grep's exit status: the "cite local docs"
# gate's first version passed while grep was printing real hits, because one shipped path (the
# hostile symlink-cycle fixture) is a directory, grep errored on it, and the non-zero exit
# masked every match.
grep_shipped() { # grep_shipped <ERE> [path-to-skip...] — prints hits in shipped files
  local re="$1"; shift
  printf '%s\n' "$SHIPPED" | /usr/bin/grep -vxF -f <(printf '%s\n' "$@" ) \
    | xargs /usr/bin/grep -d skip -sniE "$re" 2>/dev/null
}

# The forbidden-name list lives in its own file so this gate is not written in terms of the
# very strings it forbids — an earlier version of this check matched its own source line.
printf '%-34s ' "no origin-workspace detail"
PAT="$(grep -vE '^\s*(#|$)' tests/origin-detail.pattern | paste -sd'|' -)"
if [ -z "$PAT" ]; then
  echo "FAILED — tests/origin-detail.pattern is empty; this gate would pass vacuously"; fail=1
elif [ "$nship" -lt 50 ]; then
  echo "FAILED — only $nship shipped files computed; the shipped-set derivation is broken"; fail=1
elif hits="$(grep_shipped "$PAT" tests/origin-detail.pattern)" && [ -n "$hits" ]; then
  echo "FAILED — a shipped file carries origin-workspace detail"; fail=1
  printf '%s\n' "$hits" | head -20 | sed 's/^/    /'
else echo "OK ($nship shipped files)"; fi

# A shipped file must not point at a file that won't be there. Caught on its first run:
# README.md linked into the local-only design spec — a dead link in the public README, latent
# since the specs were made local-only on 2026-07-28. .gitignore is skipped because it is the
# file that DEFINES the local-only set, so it must name it.
printf '%-34s ' "shipped files don't cite local docs"
hits="$(grep_shipped 'docs/(findings|superpowers)|CLAUDE\.local\.md' .gitignore)"
if [ -n "$hits" ]; then
  echo "FAILED — a shipped file references a local-only doc"; fail=1
  printf '%s\n' "$hits" | head -20 | sed 's/^/    /'
else echo "OK"; fi

# The invariant is that shared plugin files are reached via ${CLAUDE_PLUGIN_ROOT}, never by
# traversal — only within-plugin-root paths survive install. So a violation is `../..` used to
# reach references/ or scripts/. Prose FORBIDDING traversal, and detect-mode.sh's comment about
# rejecting a hostile `../../../etc/*`, both legitimately contain the string and must not trip
# this. (First version of this check flagged that comment — hence the narrower pattern.)
printf '%-34s ' "no ../.. traversal in payload"
if grep -rnE '\.\./\.\.[^ ]*/(references|scripts)/' skills/ references/ scripts/ 2>/dev/null; then
  echo "FAILED — a ../.. reference to a shared plugin file"; fail=1
else echo "OK"; fi

echo
[ "$fail" = 0 ] && echo "ALL GATES PASS" || echo "SOME GATES FAILED"
exit $fail
