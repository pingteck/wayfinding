#!/usr/bin/env bash
# Stage the layer2-chain fixture into a scratch workspace for a dogfood run.
#
# WHY THIS EXISTS. Each member must look like a real cloned repo, which means carrying a
# `.git` — and git cannot track a file named `.git`. The members carry `.member-repo` markers
# instead, and tests/stage-fixture.sh (shared by every workspace fixture) turns them into
# `.git` files via printf, never `git init`. Copy this fixture by hand and NONE of the three
# members is a repo: since 2026-10-14 only `.git` marks one (a bare CLAUDE.md no longer does).
# Measured: a hand copy reads as `mode=monorepo` with three Go components — a PLAUSIBLE wrong
# answer, which is worse than an empty one. This wrapper adds the seeds.
set -uo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/fixtures/layer2-chain"
DEST="${1:?usage: stage-layer2-chain.sh <dest-dir> [seed: full|onboard-hub|audit-broken]}"
SEED="${2:-}"
bash "$(dirname "$SRC")/../stage-fixture.sh" "$SRC" "$DEST" || exit 2   # .member-repo -> .git
# Optional starting index for dogfood Checks 2–4 (tests/seeds/layer2-<seed>.md). Each seed is
# a known pre-state; tests/layer2-seeds.test.sh proves the graders can fail against each one.
if [ -n "$SEED" ]; then
  f="$(dirname "$SRC")/../seeds/layer2-$SEED.md"
  [ -f "$f" ] || { echo "unknown seed: $SEED"; exit 2; }
  cp "$f" "$DEST/workspace-index.md"
fi
echo "staged: $DEST${SEED:+ (seed: $SEED)}"
