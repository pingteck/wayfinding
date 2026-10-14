#!/usr/bin/env bash
# Path-existence guard for Layer 1-2 docs. Arg-free of user paths beyond a scan dir.
#
# Usage: check-doc-paths.sh [<scan-dir>]   (defaults to ".")
#
# Recognized reference = a markdown link target [..](./x) or [..](path/to/x)
# with a repo-relative or ./ prefix. Ignored: fenced code blocks, URLs
# (http(s)://), ~-paths, /UPPER/PLACEHOLDER/-style example paths, and
# in-page #anchors. References whose first path segment names a sibling
# member-repo dir (a dir, sibling to the scanned md's directory, that is
# present and has its own .git) are skipped with a note, not failed: such
# refs point into another repo's tree, which this guard does not enumerate.
# No repo names are hardcoded. Only .git marks a member repo: a bare
# CLAUDE.md is a per-directory guide (monorepos carry them), and treating it
# as a repo marker silently skipped dead links into those dirs.
set -uo pipefail
SCAN_DIR="${1:-.}"
missing=0

# NOTE on subshell scope: both loops below are fed via process substitution
# / here-string, never via a `| while` pipe. A `cmd | while ...; do ...; done`
# would run the while loop in a subshell (the right side of a pipe), so any
# `missing=1` set inside it would be lost when the subshell exits and the
# script would wrongly exit 0. Feeding loops from `< <(...)` or `<<< "$var"`
# keeps the loop body in the current shell so `missing` survives.
while IFS= read -r -d '' md; do
  # Strip fenced code blocks, then extract markdown link targets.
  refs="$(awk 'BEGIN{fence=0} /^```/{fence=!fence; next} !fence{print}' "$md" \
    | grep -oE '\]\(([^)]+)\)' | sed -E 's/^\]\(//; s/\)$//')"
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    case "$ref" in
      http://*|https://*) continue ;;   # URLs
      \~*) continue ;;                  # ~-paths
      /[A-Z]*) continue ;;              # /UPPER/PLACEHOLDER/ example paths
      \#*) continue ;;                  # in-page anchors
    esac
    # Only check ./relative or repo-relative refs
    case "$ref" in
      ./*) : ;;
      [a-zA-Z0-9_]*) : ;;
      *) continue ;;
    esac
    target="$(dirname "$md")/${ref%%#*}"
    # Skip references whose first path segment is a present sibling member
    # repo (a dir, sibling to $md's dir, with its own .git).
    # Generic — no repo names hardcoded.
    ref_nodot="${ref#./}"
    first_seg="${ref_nodot%%/*}"
    sib_dir="$(dirname "$md")/$first_seg"
    if [ -d "$sib_dir" ] && [ -e "$sib_dir/.git" ]; then
      # Plugin-authored delegation pointers are OUR files, not third-party repo content —
      # they must be existence-checked even when they live inside a member repo.
      case "${ref##*/}" in
        workspace-index.md|*.index.md) ;;   # fall through to the existence check below
        *)
          echo "note: skipping sibling-repo ref (may be absent): $ref"
          continue
          ;;
      esac
    fi
    if [ ! -e "$target" ]; then
      echo "MISSING: $md -> $ref"
      missing=1
    fi
  done <<< "$refs"
done < <(find "$SCAN_DIR" -name '*.md' -print0)

exit $missing
