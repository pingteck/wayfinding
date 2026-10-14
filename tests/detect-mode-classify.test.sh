#!/usr/bin/env bash
# Classification gate: the shared monorepo predicate, the same-ecosystem veto, and
# `mode=plain-repo`. Guards the findings adjudicated in
# the F2 red-team and 25-repo ecosystem corpus.
#
# WHY THESE FIXTURES. The first F2 design passed the ENTIRE pre-existing suite while
# carrying a Critical defect. These exist so that can't happen again — each one fails
# under some plausible-but-wrong version of this fix:
#
#   go-js-satellites   alertmanager: Go root module, ONLY JS satellites -> VETO -> plain-repo.
#                      The motivating case. `internal/tools/go.mod` is present ON PURPOSE:
#                      a raw manifest scan reads it as a same-ecosystem sibling and wrongly
#                      skips the veto; enumerate_components calls it TOOLING, so the real
#                      component set is the three JS dirs. The veto MUST be computed over
#                      emitted component units, not a manifest scan.
#   go-multi-module    consul/vault: Go root module WITH genuine go.mod siblings plus a JS
#                      ui/ -> NO veto. Same superficial shape as the above, opposite answer.
#                      A go.mod-only veto (proposed by BOTH red-team reviewers) fails here.
#   maven-ws           REGRESSION GUARD. The rejected design demoted this from mixed to
#                      multi-repo and made core/api/web unreachable by any invocation.
#   gradle-groovy      Gradle multi-project, Groovy DSL (`build.gradle`).
#   gradle-kts         The same project in the Kotlin DSL. `.kts` was missing from every
#                      manifest list until 2026-10-14: okhttp (36 `.kts` modules) read as a
#                      plain repo with ZERO components; it now yields all 36.
#   gradle-mixed-dsl   Root `.kts` over Groovy children — the normal state of a DSL migration.
#   py-mixed-manifests Root pyproject.toml over setup.py packages. These two guard the veto's
#                      same-ECOSYSTEM rule: it compared exact filenames, so recognising `.kts`
#                      alone silently demoted mixed-DSL builds to plain-repo (suite stayed green).
#   py-tooling-root    Python monorepo whose root pyproject.toml holds ONLY [tool.ruff].
#   nx-deep            nx.json is the ONLY signal (projects nested past the one-level scan).
#                      Guards has_workspace_config surviving as a clause.
#   rootdot            `.` declared as a workspace member with no root manifest.
#   per-dir-agent-docs pnpm monorepo with per-directory CLAUDE.md / AGENTS.md one level down
#                      (shape measured in getsentry/sentry, PostHog/posthog, vercel/next.js).
#                      Under the old "CLAUDE.md marks a repo" rule this read as a MIXED
#                      WORKSPACE of fake repos `docs`/`web` and every real component vanished.
#                      Only `.git` marks a member repo now.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/detect-mode.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0

for pair in go-js-satellites:plain-repo go-multi-module:monorepo maven-ws:mixed \
            gradle-groovy:monorepo gradle-kts:monorepo gradle-mixed-dsl:monorepo py-mixed-manifests:monorepo per-dir-agent-docs:monorepo py-tooling-root:monorepo nx-deep:monorepo rootdot:monorepo; do
  fx="${pair%%:*}"; mode="${pair##*:}"
  out="$TMP/$fx.out"
  bash "$HERE/stage-fixture.sh" "$HERE/fixtures/classify/$fx" "$TMP/ws/$fx" \
    && bash "$SCRIPT" "$TMP/ws/$fx" > "$out" 2>&1
  printf '%-20s ' "$fx:"
  bash "$HERE/grade-detect-mode.sh" "classify-$fx" "$out" "$mode" || { fail=1; sed 's/^/    /' "$out"; }
done

# R6: exit status must be 0 for EVERY mode. A mode meaning "classified confidently" that
# reports failure invites an agent to retry or bail instead of trusting the output.
for fx in go-js-satellites go-multi-module maven-ws nx-deep; do
  bash "$HERE/stage-fixture.sh" "$HERE/fixtures/classify/$fx" "$TMP/ws/$fx" \
    && bash "$SCRIPT" "$TMP/ws/$fx" >/dev/null 2>&1
  rc=$?
  [ "$rc" = 0 ] || { echo "MISS: $fx exited $rc, expected 0"; fail=1; }
done

# NO DEDUP GUARD HERE, DELIBERATELY — and the reason matters if you are tempted to add one.
#
# Regression b786828: enumerate_components emits the same unit twice when a path is BOTH
# declared and found by the additive scan, and is_monorepo's `sort -u` stops that inflating
# the component count. That used to be observable through single-component-member's MODE.
# It no longer is: double-emission requires a declared member, which requires a workspace
# config, which now promotes the repo through the config clause regardless of the count. So
# the dedup is belt-and-braces, not load-bearing, and no end-to-end fixture can distinguish
# a deduped count from a raw one.
#
# A guard was written for this and then deleted because it was VACUOUS — it applied its own
# `sort -u` before asserting, so it would have passed with the dedup removed (verified by
# mutating the script). A test that cannot fail is worse than no test: it reports coverage
# that does not exist. Keep the `sort -u` in is_monorepo anyway — it costs nothing and stops
# the bug returning if a future change makes the count load-bearing again.

[ "$fail" = 0 ] && echo "CLASSIFY OK" || echo "CLASSIFY FAILED"
exit $fail
