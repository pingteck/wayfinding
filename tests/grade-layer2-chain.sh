#!/usr/bin/env bash
# Grades a generated workspace-index.md against the Layer-2 doc-ablation fixture
# (`tests/fixtures/layer2-chain/`), which reproduces finding F1 —
# the 2026-07-26 OSS reconnaissance.
#
# HOW IT GRADES. Each repo's real entry point is a CANARY token that appears in exactly ONE
# file, so its presence in the index proves which source was actually read. Nothing about
# these names is guessable from the directory listing or the manifests.
#
#   quarryd       ONLY in redirect-svc/AGENTS.md      <- reachable ONLY by following the
#                                                        11-byte `@AGENTS.md` redirect
#   beaconize     ONLY in agents-only-svc/AGENTS.md   <- reachable only if AGENTS.md is read
#                                                        when no CLAUDE.md exists at all
#   lattice-run   ONLY in readme-only-svc/README.md   <- the README tier
#
# NEGATIVE canary — the one that catches "read something, but the wrong thing":
#   legacy-start  ONLY in redirect-svc/README.md, and marked DEPRECATED there. An index
#                 citing it read the README instead of following the redirect. Passing the
#                 positive check while also tripping this is a WORSE result than finding
#                 nothing, because it looks authoritative and is wrong.
set -uo pipefail
IDX="${1:?usage: grade-layer2-chain.sh <path-to-generated-workspace-index.md>}"
[ -f "$IDX" ] || { echo "MISS: no index at $IDX"; exit 1; }
fail=0

check_pos() { # check_pos <canary> <what it proves>
  if grep -qiF "$1" "$IDX"; then
    printf '  PASS  %-14s %s\n' "$1" "$2"
  else
    printf '  MISS  %-14s %s\n' "$1" "$2"; fail=1
  fi
}
check_neg() {
  if grep -qiF "$1" "$IDX"; then
    printf '  MISS  %-14s WRONG SOURCE: %s\n' "$1" "$2"; fail=1
  else
    printf '  PASS  %-14s (correctly absent)\n' "$1"
  fi
}

echo "Layer-2 source chain:"
check_pos quarryd     "followed the 11-byte @AGENTS.md redirect (F1)"
check_pos beaconize   "read AGENTS.md where no CLAUDE.md exists"
check_pos lattice-run "fell through to README.md"
check_neg legacy-start "cited the DEPRECATED README entry point instead of AGENTS.md"

# All three repos must appear as H2s at all.
for r in redirect-svc agents-only-svc readme-only-svc; do
  grep -qE "^## .*$r" "$IDX" || { printf '  MISS  %-14s no H2 for this repo\n' "$r"; fail=1; }
done

# Cross-repo edges live ONLY in prose (finding F6): manifests cannot encode them. If the
# chain worked, at least one repo's entry names another repo.
edges=$(grep -ciE 'redirect-svc|agents-only-svc|readme-only-svc' "$IDX")
[ "${edges:-0}" -ge 4 ] || { echo "  MISS  cross-repo edges: only $edges mentions; prose edges look unread"; fail=1; }

[ "$fail" = 0 ] && echo "LAYER2 OK" || echo "LAYER2 FAILED"
exit $fail
