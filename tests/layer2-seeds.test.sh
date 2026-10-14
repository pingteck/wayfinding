#!/usr/bin/env bash
# Mechanical gate for the multi-repo dogfood seeds (tests/seeds/layer2-*.md) — proves every
# instrument the agent-graded Checks 2–4 rely on can actually FAIL, before an agent is spent.
#
# WHY THIS EXISTS. The first written versions of dogfood Checks 2 and 3 (2026-07-28) would both
# have passed vacuously or false-failed, and nothing caught it until someone read the skills:
#   * Check 2 onboarded a repo that was ALREADY indexed. onboard's stop table says "target
#     already has an H2 → Stop", so a correct agent writes nothing and the grader passes on an
#     untouched index. The hub seed below has agents-only-svc ABSENT, so onboarding it is real.
#   * Check 3 expected "a gap flag, not a section". onboard writes a section for a docs-free
#     repo (Stack/Entry from manifests, Purpose "not documented"), so that spec failed a
#     correct run.
# And gate1 (grade-onboard-component.sh) hardwired the monorepo field label, so it could not
# grade a multi-repo index at all — its control went RED on a correct pair.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/grade-onboard-component.sh"
S="$HERE/seeds"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
export LINKS_FIELD='Cross-repo links:'

green() { if "$@" >/dev/null 2>&1; then printf '  PASS  %s\n' "$LABEL"; else printf '  FAIL  %s (rejected a CORRECT result)\n' "$LABEL"; "$@" 2>&1 | sed 's/^/          /' | head -15; fail=1; fi; }
red()   { if "$@" >/dev/null 2>&1; then printf '  FAIL  %s — stayed GREEN on a broken result\n' "$LABEL"; fail=1; else printf '  PASS  %s\n' "$LABEL"; fi; }
changed() { cmp -s "$1" "$2" && { printf '  FAIL  %s — MUTATION IS A NO-OP\n' "$LABEL"; fail=1; return 1; }; return 0; }

AGENTS_SECTION='
## agents-only-svc

- **Purpose:** Rules engine. Evaluates thresholds against the ingest stream and raises
  notices.
- **Role:** Rules/eventing service — sits between ingest and the exporter.
- **Entry points:** The `beaconize` binary, run against a rules directory.
- **Cross-repo links:** Consumes the stream `redirect-svc` publishes to the internal bus;
  exposes an HTTP API that `readme-only-svc` scrapes.
- **Stack:** Go 1.25, embedded BoltDB.
  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._'

echo "seed integrity"
LABEL="layer2-full.md is byte-identical to the oracle body (no drift)"
awk '/^---[[:space:]]*$/{exit} {print}' "$HERE/expected-layer2-chain-index.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$TMP/body"
green cmp -s "$TMP/body" "$S/layer2-full.md"
LABEL="no seed carries the oracle's grader notes (legacy-start would trip the negative canary)"
red /usr/bin/grep -lE 'legacy-start|Notes for graders' "$S"/layer2-*.md

echo "Check 2 instrument — onboard the hub (agents-only-svc) into the hub seed"
printf 'component=agents-only-svc\ntouched=redirect-svc readme-only-svc\n' > "$TMP/allowed"
# one CORRECT result: section appended, both siblings' links fields gain the back-link
{ cat "$S/layer2-onboard-hub.md"; printf '%s\n' "$AGENTS_SECTION"; } \
  | sed -e '/^## redirect-svc/,/^## /s/^- \*\*Cross-repo links:\*\* None recorded yet\./- **Cross-repo links:** Publishes to `agents-only-svc` over the internal bus./' \
        -e '/^## readme-only-svc/,/^## /s/^- \*\*Cross-repo links:\*\* None recorded yet\./- **Cross-repo links:** Scrapes the HTTP API exposed by `agents-only-svc`./' > "$TMP/c2-good"
LABEL="control: a correct onboard passes gate1"
green bash "$G" gate1 "$S/layer2-onboard-hub.md" "$TMP/c2-good" "$TMP/allowed"
LABEL="control: and passes the structural grader"
green bash "$HERE/grade-multirepo-index.sh" "$TMP/c2-good" redirect-svc agents-only-svc readme-only-svc \
  --unprofiled redirect-svc,agents-only-svc,readme-only-svc

LABEL="M-a append-and-stop: section added, NO sibling back-linked (the skill's defining failure)"
{ cat "$S/layer2-onboard-hub.md"; printf '%s\n' "$AGENTS_SECTION"; } > "$TMP/m"
changed "$S/layer2-onboard-hub.md" "$TMP/m" && red bash "$G" gate1 "$S/layer2-onboard-hub.md" "$TMP/m" "$TMP/allowed"
LABEL="M-b one sibling back-linked, the other forgotten"
sed '/^## readme-only-svc/,/^## /s/Scrapes the HTTP API exposed by `agents-only-svc`\./None recorded yet./' "$TMP/c2-good" > "$TMP/m"
changed "$TMP/c2-good" "$TMP/m" && red bash "$G" gate1 "$S/layer2-onboard-hub.md" "$TMP/m" "$TMP/allowed"
LABEL="M-c a sibling's Purpose edited (outside the allowed change set)"
sed 's/Ingest service for meter readings\./Ingest service for meter and sensor readings./' "$TMP/c2-good" > "$TMP/m"
changed "$TMP/c2-good" "$TMP/m" && red bash "$G" gate1 "$S/layer2-onboard-hub.md" "$TMP/m" "$TMP/allowed"
LABEL="M-d the blockquote 'fixed' (containment — what the onboard RED arms did)"
sed 's/^> Ingest, rules and metrics services/> Three services: ingest, rules and metrics,/' "$TMP/c2-good" > "$TMP/m"
changed "$TMP/c2-good" "$TMP/m" && red bash "$G" gate1 "$S/layer2-onboard-hub.md" "$TMP/m" "$TMP/allowed"

echo "gate1 additivity — an 'edge' is a UNIT name on the links line, not every word on it"
# Pre-state: readme-only-svc not yet indexed, so agents-only-svc's links name only redirect-svc.
# Onboarding readme-only-svc must KEEP that edge and ADD the back-link. Until 2026-10-14 gate1
# treated every word on the line as an edge, so a correct rewording false-failed, and so did
# replacing a "None recorded yet." placeholder (the hub control above).
printf 'component=readme-only-svc\ntouched=agents-only-svc\n' > "$TMP/allowedR"
awk '/^## readme-only-svc/{s=1} /^## /&&!/readme-only-svc/{s=0} !s' "$S/layer2-full.md" \
  | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
  | sed 's/^  exposes an HTTP API that `readme-only-svc` scrapes\.$/  feeds its notices onward./' > "$TMP/r-before"
LABEL="(setup) the pre-state really lacks readme-only-svc everywhere"
red /usr/bin/grep -q 'readme-only-svc' "$TMP/r-before"
LABEL="control: back-link added, existing edge kept verbatim"
green bash "$G" gate1 "$TMP/r-before" "$S/layer2-full.md" "$TMP/allowedR"
sed 's/^- \*\*Cross-repo links:\*\* Consumes the stream `redirect-svc` publishes to the internal bus;$/- **Cross-repo links:** Reads what `redirect-svc` puts on the bus;/' "$S/layer2-full.md" > "$TMP/r-reword"
LABEL="a correct REWORDING of the links line (edge to redirect-svc kept) passes"
changed "$S/layer2-full.md" "$TMP/r-reword" && green bash "$G" gate1 "$TMP/r-before" "$TMP/r-reword" "$TMP/allowedR"
sed -e 's/^- \*\*Cross-repo links:\*\* Consumes the stream `redirect-svc` publishes to the internal bus;$/- **Cross-repo links:** Reads the internal bus;/' "$S/layer2-full.md" > "$TMP/m"
LABEL="M-f the line rewritten and the pre-existing edge to redirect-svc LOST"
changed "$S/layer2-full.md" "$TMP/m" && red bash "$G" gate1 "$TMP/r-before" "$TMP/m" "$TMP/allowedR"

echo "Check 3 instrument — onboard a docs-free repo (unprofiled-svc) into the full seed"
printf 'component=unprofiled-svc\ntouched=\n' > "$TMP/allowed3"
{ cat "$S/layer2-full.md"; printf '\n## unprofiled-svc\n\n- **Purpose:** Not documented in the repo.\n- **Role:** Not documented in the repo.\n- **Entry points:** Not documented in the repo.\n- **Cross-repo links:** None documented.\n- **Stack:** Go 1.25.\n  _Layer-4 baseline only; Layer-3 profile TODO — see ${CLAUDE_PLUGIN_ROOT}/references/stack-profile-format.md._\n'; } > "$TMP/c3-good"
LABEL="control: a correct docs-free onboard passes gate1 (nothing else touched)"
green bash "$G" gate1 "$S/layer2-full.md" "$TMP/c3-good" "$TMP/allowed3"
LABEL="M-e an existing section edited while onboarding a repo with NO edges"
sed 's/Scrapes the HTTP API exposed by `agents-only-svc`\./Scrapes the HTTP API exposed by `agents-only-svc`; sits beside `unprofiled-svc`./' "$TMP/c3-good" > "$TMP/m"
changed "$TMP/c3-good" "$TMP/m" && red bash "$G" gate1 "$S/layer2-full.md" "$TMP/m" "$TMP/allowed3"

echo "Check 4 instrument — the audit seed's two defects are each detectable"
LABEL="one-sided edge: structural grader goes RED"
red bash "$HERE/grade-multirepo-index.sh" "$S/layer2-audit-broken.md" redirect-svc agents-only-svc readme-only-svc
LABEL="dead link: path guard goes RED"
mkdir -p "$TMP/ws4" && cp "$S/layer2-audit-broken.md" "$TMP/ws4/workspace-index.md"
red bash "$HERE/../scripts/check-doc-paths.sh" "$TMP/ws4/workspace-index.md"
LABEL="...and the unbroken full seed is GREEN on both (the defects are the only difference)"
cp "$S/layer2-full.md" "$TMP/ws4/workspace-index.md"
green bash -c "bash '$HERE/../scripts/check-doc-paths.sh' '$TMP/ws4/workspace-index.md' && bash '$HERE/grade-multirepo-index.sh' '$S/layer2-full.md' redirect-svc agents-only-svc readme-only-svc"

echo "staging"
LABEL="stage-layer2-chain.sh <dest> <seed> writes that seed as workspace-index.md"
bash "$HERE/stage-layer2-chain.sh" "$TMP/ws" onboard-hub >/dev/null 2>&1
green cmp -s "$S/layer2-onboard-hub.md" "$TMP/ws/workspace-index.md"

echo
[ "$fail" = 0 ] && echo "SEEDS OK" || echo "SEEDS FAILED"
exit $fail
