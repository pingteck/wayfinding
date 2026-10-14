#!/usr/bin/env bash
# Structural grader for a MULTI-REPO Layer-1 workspace index, per
# ${CLAUDE_PLUGIN_ROOT}/references/layer1-index-format.md.
#
#   usage: grade-multirepo-index.sh <index.md> <repo>[=<stack-regex>] ... \
#            [--unprofiled <repo,repo>] [--profiled <repo,repo>]
#   e.g.   grade-multirepo-index.sh workspace-index.md \
#            redirect-svc='Chi|pgx' agents-only-svc='BoltDB' readme-only-svc='zerolog' \
#            --unprofiled redirect-svc,agents-only-svc,readme-only-svc
#
# --unprofiled / --profiled assert the Layer-4-baseline marker in BOTH directions. Omit them
# and the marker is not checked at all — which is how this grader shipped on 2026-07-28, and
# it let a hand-authored oracle that was MISSING the marker on all three repos pass clean.
#
# WHAT REPLACED WHAT. This supersedes `grade-index.sh`, which hardcoded one private
# workspace's two repo names and its stack strings, and so failed BY DESIGN against any other
# workspace — it was the acceptance spine and it could not be published. This grader takes the
# repo set and the stack facts as ARGUMENTS, so it is genuinely structural: point it at any
# multi-repo workspace with that workspace's own repo names.
#
# THE STACK REGEX IS OPTIONAL BUT LOAD-BEARING. Its job is to prove the Stack field carries a
# fact that was READ rather than guessed, so pass a token that occurs in exactly one place in
# the target workspace. It is checked WITHIN the repo's own section — a whole-file grep would
# pass an index that put the right token under the wrong repo (mutation M8).
#
# THE BOTH-ENDPOINTS RULE IS CONDITIONAL, NOT TOTAL. "Every edge appears on both endpoints"
# means: if A's section names B, B's section must name A. It does NOT mean every pair of repos
# must be connected. A grader written the total way rejects a correct index of any workspace
# whose repos are not a complete graph — the layer2-chain fixture is a line, so redirect-svc
# and readme-only-svc legitimately have no edge. Zero edges overall IS a failure, though:
# with no edges the reciprocity check is vacuous and the prose plainly went unread.
#
# Mutation-tested by grade-multirepo-index.test.sh — if you add a check here, add its mutation
# there, or the check is unproven.
set -uo pipefail

IDX="${1:?usage: grade-multirepo-index.sh <index.md> <repo>[=<stack-regex>] ...}"; shift
[ $# -ge 1 ] || { echo "usage: grade-multirepo-index.sh <index.md> <repo>[=<stack-regex>] ..."; exit 2; }
[ -f "$IDX" ] || { echo "MISS: no index at $IDX"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()   { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  MISS  %s\n' "$1"; fail=1; }

# Headings that are legitimately not repo sections.
NOTE_HEADINGS='^(Tooling & root config|No-manifest candidates|Notes|Notes for graders.*)$'

REPOS=(); STACKRE=(); UNPROFILED=""; PROFILED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unprofiled) UNPROFILED="$UNPROFILED,${2:?--unprofiled needs a repo list}"; shift 2;;
    --profiled)   PROFILED="$PROFILED,${2:?--profiled needs a repo list}";       shift 2;;
    --*) echo "unknown option: $1"; exit 2;;
    *=*) REPOS+=("${1%%=*}"); STACKRE+=("${1#*=}"); shift;;
    *)   REPOS+=("$1");       STACKRE+=("");        shift;;
  esac
done
in_list() { case ",$(printf '%s' "$2" | tr -d ' '),"  in *",$1,"*) return 0;; esac; return 1; }

# A repo in BOTH lists is a contradictory spec, not a preference. Silently letting one win
# makes the marker check quietly untestable in one direction — which it was, for exactly one
# run of this file, until M12 landed and exposed it.
for r in "${REPOS[@]}"; do
  if in_list "$r" "$UNPROFILED" && in_list "$r" "$PROFILED"; then
    echo "spec error: '$r' is in both --unprofiled and --profiled"; exit 2
  fi
done

# --- split the index into preamble + one file per H2 -------------------------------------
awk -v d="$TMP" '
  /^## / { n++; h=$0; sub(/^## +/,"",h); print h >> (d"/heads"); fn=sprintf("%s/sec_%d",d,n); printf "" > fn; next }
  { if (n>0) print >> sprintf("%s/sec_%d",d,n); else print >> (d"/preamble") }
' "$IDX"
touch "$TMP/heads" "$TMP/preamble"

# --- C0/C1: workspace-level shape ---------------------------------------------------------
grep -qE '^# +[^[:space:]]' "$TMP/preamble" && ok "H1 workspace name" || bad "no H1 workspace name"
grep -qE '^> +[^[:space:]]'  "$TMP/preamble" && ok "blockquote summary" || bad "no blockquote summary line"

# --- locate each named repo's section ------------------------------------------------------
SECOF=()
n="$(wc -l < "$TMP/heads" | tr -d ' ')"
for i in "${!REPOS[@]}"; do
  r="${REPOS[$i]}"; found=""
  for ((s=1; s<=n; s++)); do
    h="$(sed -n "${s}p" "$TMP/heads")"
    case "$h" in *"$r"*) found="$s"; break;; esac
  done
  SECOF[$i]="$found"
  [ -n "$found" ] && ok "section for $r" || bad "no H2 section for $r"
done

# --- C3: no invented repo sections ----------------------------------------------------------
for ((s=1; s<=n; s++)); do
  h="$(sed -n "${s}p" "$TMP/heads")"
  [[ "$h" =~ $NOTE_HEADINGS ]] && continue
  known=""
  for r in "${REPOS[@]}"; do case "$h" in *"$r"*) known=1;; esac; done
  [ -n "$known" ] || bad "extra H2 '$h' — not a repo in this workspace (invented?)"
done

# --- C4/C5: per-section fields and stack fact ------------------------------------------------
for i in "${!REPOS[@]}"; do
  r="${REPOS[$i]}"; s="${SECOF[$i]}"; [ -n "$s" ] || continue
  f="$TMP/sec_$s"
  for label in 'Purpose' 'Role' 'Entry points' 'Cross-repo links' 'Stack'; do
    # a label line: optional list marker / heading hashes / bold markers, then the label
    grep -qiE "^[-*#[:space:]]*\**${label}\**[[:space:]]*:?" "$f" \
      && ok "$r: $label field" || bad "$r: no '$label' field"
  done
  # Unprofiled-marker SELECTIVITY. Both directions matter and they fail differently: a missing
  # marker silently claims a Layer-3 profile that does not exist, while a spurious one tells a
  # reader to go write a profile that is already bundled. Checked per repo, inside its own
  # section, for the same reason the stack fact is.
  if in_list "$r" "$UNPROFILED"; then
    grep -qF 'Layer-4 baseline only; Layer-3 profile TODO' "$f" \
      && ok "$r: unprofiled marker present" \
      || bad "$r: no 'Layer-4 baseline only; Layer-3 profile TODO' marker, but no bundled profile matches it"
  elif in_list "$r" "$PROFILED"; then
    grep -qF 'Layer-4 baseline only' "$f" \
      && bad "$r: carries the unprofiled marker, but a bundled stack profile matches it" \
      || ok "$r: correctly unmarked (a bundled profile matches)"
  fi

  re="${STACKRE[$i]}"
  [ -n "$re" ] || continue
  # the stack fact must be in THIS repo's section, not merely somewhere in the document
  grep -qiE "$re" "$f" && ok "$r: stack names a read fact (/$re/)" \
    || bad "$r: Stack does not name /$re/ in this section (guessed, or filed under another repo)"
done

# --- C6/C7: conditional both-endpoints reciprocity -------------------------------------------
edges=0
for i in "${!REPOS[@]}"; do
  for j in "${!REPOS[@]}"; do
    [ "$i" = "$j" ] && continue
    a="${REPOS[$i]}"; b="${REPOS[$j]}"
    sa="${SECOF[$i]}"; sb="${SECOF[$j]}"
    [ -n "$sa" ] && [ -n "$sb" ] || continue
    grep -qF "$b" "$TMP/sec_$sa" || continue      # A does not claim an edge to B
    edges=$((edges+1))
    if grep -qF "$a" "$TMP/sec_$sb"; then ok "edge $a -> $b is on both endpoints"
    else bad "one-sided edge: $a's section names $b, but $b's section never names $a"; fi
  done
done
if [ "$edges" = 0 ]; then
  bad "zero cross-repo edges asserted — the both-endpoints check is vacuous and the prose looks unread"
else
  ok "$edges cross-repo edge mention(s) asserted"
fi

echo
[ "$fail" = 0 ] && echo "MULTIREPO INDEX OK" || echo "MULTIREPO INDEX FAILED"
exit $fail
