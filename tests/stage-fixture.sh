#!/usr/bin/env bash
# Stage a committed fixture into a scratch dir, turning every `.member-repo` marker into a real
# `.git` file.
#
#   usage: stage-fixture.sh <fixture-dir> <dest-dir>
#
# WHY. Only a `.git` entry marks an independent member repo (scripts/detect-mode.sh,
# is_independent_repo). Git cannot track a file named `.git` — it drops it SILENTLY — so a
# committed workspace fixture cannot carry one. Until 2026-10-14 the detector also accepted a
# bare `CLAUDE.md` as the marker, which is how committed fixtures got away without `.git`; it
# was also a product defect: Claude Code encourages per-directory CLAUDE.md files, so any
# monorepo with one a level down (getsentry/sentry, PostHog/posthog, ...) read as a multi-repo
# workspace and its real components vanished. Fixtures now say what they mean with a marker the
# product never reads, and this script materializes it — printf only, never `git init`.
set -uo pipefail
SRC="${1:?usage: stage-fixture.sh <fixture-dir> <dest-dir>}"
DEST="${2:?usage: stage-fixture.sh <fixture-dir> <dest-dir>}"
[ -d "$SRC" ] || { echo "no such fixture: $SRC"; exit 2; }
rm -rf "$DEST"; mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"
find "$DEST" -type f -name .member-repo | while IFS= read -r m; do
  d="$(dirname "$m")"
  printf 'gitdir: /nonexistent/%s.git\n' "$(basename "$d")" > "$d/.git"
  rm -f "$m"
done
