#!/usr/bin/env bash
# Declared-member-set gate for scripts/detect-mode.sh (findings F3/F4/F5).
#
# WHY THESE FIXTURES EXIST. Every other fixture in this repo was authored by us, so none of
# them could reproduce what real repos do. These three are distilled from measured shapes in
# the OSS reconnaissance (findings F3/F4/F5), verified against shallow clones on
# 2026-07-26:
#
#   declared/go-workspace    <- prometheus/prometheus. Block-form `use ( ... )` including `.`,
#                               one root go.mod, ~18 manifest-less package dirs. Before the
#                               fix the detector called this a monorepo of `compliance` +
#                               `web/ui` with 18 no-manifest-candidates.
#   declared/pnpm-negation   <- vercel/turborepo. `!` negation globs, plus `docs/*` entries
#                               that ARE workspace packages (cutting against the assumption
#                               that a docs dir is a no-manifest candidate).
#   declared/root-ships-code <- grafana/grafana. Root go.mod + embed.go alongside apps/,
#                               packages/, pkg/ — root ships code with NO `.` declaration,
#                               so it exercises a different trigger than go-workspace.
#
# Two more guard the failure modes most likely to be reintroduced:
#
#   declared/negation-substring  `!packages/turbo` must NOT also suppress
#                               `packages/turbo-extra`. Substring-vs-whole-token is THE
#                               recurring defect class on this project (six occurrences to
#                               date, including one during the rename). The newline
#                               delimiters in `is_negated` are what make this pass; drop
#                               them and this fixture is the only thing that notices.
#   declared/go-single-line     the non-block `use ./x` form, with one member nested THREE
#                               levels deep. The depth is deliberate: the additive one-level
#                               scan cannot reach `internal/nested/svc-c`, so this unit can
#                               only come from the declared reader — which is what makes the
#                               single-line parse observable at all. (A shallow version of
#                               this fixture passed on the pre-fix script by accident, via
#                               the glob fallback, and proved nothing.) It also has no root
#                               go.mod and no `.` entry, so it is the NEGATIVE case for
#                               root_ships_code — the F5 fix must not over-fire and suppress
#                               the legitimate `no-manifest-candidate internal`.
#
# THE CONTRACT UNDER TEST — "authoritative + additive":
#   1. Declared entries are honored exactly: globs expand, `!` negations SUBTRACT, `.` is
#      representable (as `root-component .`), and declared paths emit at their declared
#      depth however deep that is.
#   2. The one-level additive scan still runs, so an UNDECLARED but manifested directory is
#      still found (`web/ui` in go-workspace).
#   3. A negated path is suppressed even when the additive scan would otherwise find it
#      (`packages/turbo` in pnpm-negation — this is the load-bearing negation assertion;
#      `examples/non-monorepo` is shadowed by roll-up and does NOT independently test it).
#   4. When the root itself ships code, manifest-less child dirs are NOT
#      no-manifest-candidates — they are packages of the root module, i.e. explained.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/detect-mode.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
# `fixture:expected-mode` — most are monorepo; single-component-member is a WORKSPACE fixture,
# so the mode is per-fixture, not a constant.
#
# single-component-member expects `mixed` / `monorepo-member one-member`. It previously
# expected `multi-repo` / `repo one-member`, which was encoding the INVERSE-F2 bug: the
# parent called a declared 1-package workspace a plain repo while the member's own run called
# it a monorepo, so the parent never delegated and the member's component was invisible. The
# shared predicate makes both answer `monorepo`. Honoring a `workspaces:` declaration that
# happens to list one package is the point — see the findings doc, R2.
for pair in go-workspace:monorepo pnpm-negation:monorepo root-ships-code:monorepo \
            negation-substring:monorepo go-single-line:monorepo \
            single-component-member:mixed cargo-exclude:monorepo; do
  fx="${pair%%:*}"; mode="${pair##*:}"
  out="$TMP/$fx.out"
  bash "$HERE/stage-fixture.sh" "$HERE/fixtures/declared/$fx" "$TMP/ws/$fx" \
    && bash "$SCRIPT" "$TMP/ws/$fx" > "$out" 2>&1
  printf '%-25s ' "$fx:"
  bash "$HERE/grade-detect-mode.sh" "declared-$fx" "$out" "$mode" || { fail=1; sed 's/^/    /' "$out"; }
done

[ "$fail" = 0 ] && echo "DECLARED OK" || echo "DECLARED FAILED"
exit $fail
