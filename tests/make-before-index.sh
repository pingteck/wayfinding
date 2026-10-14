#!/usr/bin/env bash
# Derive a "before" index from a frozen oracle: strip the LAST component section and
# degrade every line in any OTHER section that names it. Emits the allowed-change set
# consumed by grade-onboard-component.sh Gate 1 (so the gate is never derived from the
# implementation under test).
set -uo pipefail
ORACLE="${1:?usage: make-before-index.sh <oracle.md> <out-before.md> <out-allowed.txt>}"
OUT="${2:?missing out-before.md}"
ALLOWED="${3:?missing out-allowed.txt}"

# Component sections = H2s excluding the trailing note/meta sections.
is_note() {
  case "$1" in
    "Tooling & root config"|"No-manifest candidates") return 0;;
    "Notes for graders"*) return 0;;
    *) return 1;;
  esac
}

LAST=""
while IFS= read -r h; do
  is_note "$h" && continue
  LAST="$h"
done < <(grep -E '^## ' "$ORACLE" | sed -E 's/^## +//; s/[[:space:]]+$//')

[ -n "$LAST" ] || { echo "make-before-index: no component section found in $ORACLE" >&2; exit 1; }

# Strip the LAST component's section; degrade every OTHER component section's lines
# naming it. Note/meta sections (is_note()) are left byte-for-byte untouched — a leaked
# component name in their prose is harmless (nothing keys on note-section prose; the
# candidate-set logic matches component-region headings), and degrading it there would
# also mangle unrelated things it isn't meant to touch, e.g. a backtick-quoted PATH like
# `packages/ui` becoming `packages/`. Leaving them alone is both more faithful to a real
# "before" state and lets the grader diff them byte-for-byte instead of excluding them.
#
# "Naming it" means comp appears as a standalone token — bounded on both sides by
# start/end-of-string or a non-identifier character (anything but [A-Za-z0-9_-];
# hyphens count as identifier chars so kebab-case names aren't split). A raw
# substring match (no boundary check) would also fire inside unrelated tokens
# (e.g. comp="ui" is a substring of "build") and corrupt prose that never named
# the component at all. Boundary-checked, it still catches non-backtick mentions
# like the trailing path segment in a backtick-quoted path (`packages/ui`),
# because "/" and the closing backtick are both non-identifier boundary chars.
awk -v comp="$LAST" -v allowed="$ALLOWED" '
  function seclabel(l){ sub(/^## +/,"",l); sub(/[[:space:]]+$/,"",l); return l }
  function is_boundary(c){ return (c == "" || c !~ /[A-Za-z0-9_-]/) }
  # Mirrors the bash is_note() above: note/meta sections are skipped entirely by the
  # degrade call below (passed through unchanged), so they can never end up in
  # `touched=` either — that descriptor only names component sections whose
  # `Cross-component links:` line a correct run must extend with a back-link, and note
  # sections have no links field to reconcile. Component names never contain spaces, so
  # restricting `touched=` to them also keeps it safe for `for s in $TOUCHED` splitting.
  function is_note(l) {
    if (l == "Tooling & root config" || l == "No-manifest candidates") return 1
    if (l ~ /^Notes for graders/) return 1
    return 0
  }
  # Scan `line` left to right; replace every standalone occurrence of `comp`
  # with @@DROP@@, keeping non-matching text (including non-boundary hits like
  # "ui" inside "build") untouched. Sets `hit` (global) to 1 if anything matched.
  function degrade(line, comp,    out, pos, rel, idx, before, after, n, dstart, dlen) {
    out = ""; pos = 1; n = length(comp)
    while ((rel = index(substr(line, pos), comp)) > 0) {
      idx = pos + rel - 1
      before = (idx == 1) ? "" : substr(line, idx - 1, 1)
      after  = substr(line, idx + n, 1)
      if (is_boundary(before) && is_boundary(after)) {
        # A true backtick-quoted mention (`comp`) drops the backticks too, so
        # the joiner cleanup below sees a clean "and @@DROP@@" / ", @@DROP@@"
        # to collapse. A bare boundary hit inside a longer backtick-quoted
        # token (e.g. the trailing segment of `packages/ui`) only drops the
        # word itself, leaving the surrounding punctuation untouched.
        if (before == "`" && after == "`") { dstart = idx - 1; dlen = n + 2 }
        else                                { dstart = idx;     dlen = n }
        out = out substr(line, pos, dstart - pos) "@@DROP@@"
        pos = dstart + dlen
        hit = 1
      } else {
        out = out substr(line, pos, idx - pos + 1)
        pos = idx + 1
      }
    }
    out = out substr(line, pos)
    return out
  }
  /^## / {
    lbl = seclabel($0)
    instrip = (lbl == comp) ? 1 : 0
    sec = lbl
    if (instrip) next
  }
  instrip { next }
  {
    line = $0
    if (sec != "" && sec != comp && !is_note(sec) && index(line, comp) > 0) {
      hit = 0
      line = degrade(line, comp)
      if (hit) {
        touched[sec] = 1
        gsub(/,?[[:space:]]*and[[:space:]]*@@DROP@@/, "", line)
        gsub(/@@DROP@@[[:space:]]*and[[:space:]]*/, "", line)
        gsub(/,[[:space:]]*@@DROP@@/, "", line)
        gsub(/@@DROP@@[[:space:]]*,[[:space:]]*/, "", line)
        gsub(/@@DROP@@/, "", line)
        gsub(/[[:space:]]+\./, ".", line)
        gsub(/[[:space:]]+$/, "", line)
      }
    }
    print line
  }
  END {
    s = ""
    for (k in touched) s = s " " k
    printf "component=%s\n", comp > allowed
    printf "touched=%s\n", substr(s,2) >> allowed
  }
' "$ORACLE" > "$OUT"

echo "derived: $OUT (stripped '$LAST'); allowed-change set: $ALLOWED"
