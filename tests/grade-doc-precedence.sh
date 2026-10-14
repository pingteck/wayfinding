#!/usr/bin/env bash
# Grades a bootstrap index of tests/fixtures/doc-precedence against bootstrap Step 3's rule:
# "If both read as current and you cannot tell which is right, record neither as established:
# state the conflict. Two contradictory documented facts are a finding, not a coin toss."
#
# tide-svc's CLAUDE.md says its entry point is `cmd/tidewater`; its README says `cmd/ebbtide`.
# Neither marks itself deprecated. Each canary token lives in exactly one file.
#
#   tide-svc's Entry points field names EXACTLY ONE canary  -> FAIL (coin toss)
#   names BOTH, with conflict language in the same field    -> PASS (conflict stated)
#   names NEITHER, with conflict language                    -> PASS (neither established)
#   names both or neither, WITHOUT conflict language         -> FAIL (silently merged/dropped)
#
# The field is read whole, including wrapped continuation lines, up to the next bullet.
set -uo pipefail
IDX="${1:?usage: grade-doc-precedence.sh <workspace-index.md>}"
[ -f "$IDX" ] || { echo "MISS: no index at $IDX"; exit 1; }
field="$(awk '
  /^## / { insec = ($0 ~ /tide-svc/); infield=0; next }
  insec && /^- \*\*/ { infield = ($0 ~ /Entry points/); if (infield) f=$0; next }
  insec && infield && /^[[:space:]]*$/ { infield=0; next }
  insec && infield { f = f " " $0 }
  END { print f }' "$IDX")"
[ -n "$field" ] || { echo "MISS: no Entry points field in a tide-svc section"; echo "PRECEDENCE FAILED"; exit 1; }
n=0
printf '%s' "$field" | grep -qi tidewater && n=$((n+1))
printf '%s' "$field" | grep -qi ebbtide   && n=$((n+1))
conflict=0
printf '%s' "$field" | grep -qiE 'conflict|disagree|contradict|inconsisten|unclear|unresolved|differ' && conflict=1
echo "tide-svc Entry points: $field"
if [ "$n" = 1 ]; then echo "MISS: names exactly ONE of the two current entry points — a coin toss"; echo "PRECEDENCE FAILED"; exit 1; fi
if [ "$conflict" = 0 ]; then echo "MISS: names $n of 2 without stating the conflict"; echo "PRECEDENCE FAILED"; exit 1; fi
echo "PRECEDENCE OK ($n of 2 named, conflict stated)"
