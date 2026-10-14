#!/usr/bin/env bash
# Gates for onboard-a-component.
#   gate1        <before.md> <after.md> <allowed.txt>          containment + line-additivity
#   gate1-parent <parent-before.md> <parent-after.md> <member> mixed-mode parent containment
#   headings     <before.md> <after.md> <expected-delta>
#   noop         <before.md> <after.md>                        nothing was written
#   edge         <index.md> <A> <B> [--absent]                 A<->B on both endpoints (or absent)
set -uo pipefail
MODE="${1:?usage: grade-onboard-component.sh <gate1|gate1-parent|headings|noop|edge> ...}"
shift
fail=0

# The links field label differs by mode: monorepo components carry `Cross-component links:`,
# multi-repo sections carry `Cross-repo links:`. Hardwired to the monorepo label until
# 2026-10-14, which made gate1 reject EVERY correct multi-repo onboard (nothing got blanked,
# no names were found) — see tests/layer2-seeds.test.sh. Set LINKS_FIELD to grade multi-repo.
FIELD_LINKS="${LINKS_FIELD:-Cross-component links:}"
FIELD_COMPONENTS='Components:'

strip_section() { # strip_section <file> <section-name>  -> file with that H2 section removed
  # Buffers blank lines instead of printing them immediately, so the blank line that
  # separates the PRECEDING section from a stripped one is only re-emitted if stripping
  # ends at a later heading (where it becomes that heading's separator); if stripping runs
  # to EOF instead, the buffered blank is simply never flushed. Without this, a component
  # appended as the LAST section leaves a dangling blank line at absolute EOF after
  # stripping, which spuriously fails gate1's containment diff against a "before" file that
  # never had one (M3).
  awk -v comp="$2" '
    function flush(   i) { for (i=0;i<blanks;i++) print ""; blanks=0 }
    /^## / {
      lbl=$0; sub(/^## +/,"",lbl); sub(/[[:space:]]+$/,"",lbl)
      newstrip=(lbl==comp)?1:0
      if (newstrip) { instrip=1; next }
      flush(); instrip=0; print; next
    }
    instrip { next }
    /^[[:space:]]*$/ { blanks++; next }
    { flush(); print }
  ' "$1"
}

# get_field <file> <section> [field-label, default "Cross-component links:"] -> the FULL
# text of that section's field, accumulated from its "- **<field-label>**" line through
# every continuation line, stopping at the first of: a blank line, the next "- **" bullet,
# the next "## " or deeper (###+) heading, or EOF. A field that legitimately wraps (a long
# links line) must be read whole, or a correct wrapped addition false-fails
# containment/additivity. The deeper-heading stop (M1) matters because a decoy "###" line
# placed right after the field is otherwise swept in as if it were field content, letting a
# destroyed edge false-satisfy the check by merely mentioning the sibling's name under that
# decoy heading.
get_field() {
  local field="${3:-$FIELD_LINKS}"
  awk -v want="$2" -v fld="$field" '
    function trim(s){ sub(/[[:space:]]+$/,"",s); return s }
    /^## / { sec=trim($0); sub(/^## +/,"",sec); insec=(sec==want)?1:0; infield=0; next }
    /^#{3,}[[:space:]]/ { infield=0; next }
    insec && /^- \*\*/ {
      infield = (index($0, fld) > 0) ? 1 : 0
      if (infield) field=$0
      next
    }
    insec && infield && /^[[:space:]]*$/ { infield=0; next }
    insec && infield { field = field " " $0; next }
    { next }
    END { print field }
  ' "$1"
}

# names_on_links_line <file> <section> -> the set of component-name TOKENS mentioned on
# that section's Cross-component links field (accumulated, see get_field). Tokens are
# matched as whole [A-Za-z0-9_-] runs, NOT raw substrings, and backticks are NOT required
# — a correct index may state a name without backticks. Requiring backticks would
# false-fail a correct-but-unquoted mention; raw substring matching would false-satisfy
# e.g. "web" against "webpack" or "ui" against "shared-ui" fragments.
names_on_links_line() {
  get_field "$1" "$2" | awk '
    { gsub(/[^A-Za-z0-9_-]/, " "); n=split($0,a," "); for (i=1;i<=n;i++) if (a[i]!="") print a[i] }
  ' | sort -u
}

# blank_field <file> <field-label> <placeholder> <sections...> -> file with each named
# section's ENTIRE <field-label> field (start line + every continuation line) collapsed to
# a single placeholder line. Collapsing the whole field to one line (not just blanking the
# first physical line) is what lets a correct wrapped addition still diff identically
# against a before-state whose field was a single line (or vice versa) — the field's
# line-count is allowed to change, only its identity as "the allowed field" matters for
# containment. Carries the same deeper-heading stop as get_field (M1).
blank_field() {
  local f="$1" field="$2" placeholder="$3"; shift 3
  local secs=" $* "
  awk -v secs="$secs" -v fld="$field" -v ph="$placeholder" '
    function trim(s){ sub(/[[:space:]]+$/,"",s); return s }
    /^## / {
      lbl=trim($0); sub(/^## +/,"",lbl); intouched=(index(secs," " lbl " ")>0)?1:0; infield=0
      print; next
    }
    /^#{3,}[[:space:]]/ { infield=0; print; next }
    intouched && /^- \*\*/ {
      infield = (index($0, fld) > 0) ? 1 : 0
      if (infield) { print ph; next }
      print; next
    }
    intouched && infield && /^[[:space:]]*$/ { infield=0; print; next }
    intouched && infield { next }
    { print }
  ' "$f"
}

case "$MODE" in
  gate1)
    BEFORE="${1:?}"; AFTER="${2:?}"; ALLOWED="${3:?}"
    COMP="$(sed -nE 's/^component=//p' "$ALLOWED")"
    TOUCHED="$(sed -nE 's/^touched=//p' "$ALLOWED")"
    [ -n "$COMP" ] || { echo "MISS: allowed set has no component="; exit 1; }

    # 1. containment: everything outside the allowed change set must be byte-identical
    A="$(mktemp)"; B="$(mktemp)"; AFTER_STRIPPED="$(mktemp)"; DIFF="$(mktemp)"
    blank_field "$BEFORE" "$FIELD_LINKS" "@@ALLOWED@@" $TOUCHED > "$A"
    strip_section "$AFTER" "$COMP" > "$AFTER_STRIPPED"
    blank_field "$AFTER_STRIPPED" "$FIELD_LINKS" "@@ALLOWED@@" $TOUCHED > "$B"
    if ! diff -u "$A" "$B" > "$DIFF"; then
      echo "MISS: content outside the allowed change set differs:"; sed -n '1,40p' "$DIFF"; fail=1
    fi
    rm -f "$A" "$B" "$AFTER_STRIPPED" "$DIFF"

    # 2. the new section must actually exist in AFTER
    grep -qE "^## ${COMP}[[:space:]]*$" "$AFTER" || { echo "MISS: '## $COMP' absent from result"; fail=1; }

    # 3. line-additivity: each touched section keeps every UNIT name it had, and gains the
    #    component. "Name" means an indexed unit — an H2 label in BEFORE, or the component
    #    being added — not every word on the line. Until 2026-10-14 every token counted, so a
    #    correct rewording ("calls `api` over REST" -> "calls `api`'s REST API" loses "over")
    #    or replacing a "None recorded yet." placeholder false-failed as a lost edge. Losing a
    #    real unit name still fails; tests/layer2-seeds.test.sh pins both directions.
    UNITS="$(sed -nE 's/^## +//p' "$BEFORE" | sed 's/[[:space:]]*$//'; printf '%s\n' "$COMP")"
    for s in $TOUCHED; do
      before_names="$(names_on_links_line "$BEFORE" "$s" | grep -Fxf <(printf '%s\n' "$UNITS"))"
      after_names="$(names_on_links_line "$AFTER" "$s" | grep -Fxf <(printf '%s\n' "$UNITS"))"
      for n in $before_names; do
        printf '%s\n' "$after_names" | grep -qx "$n" \
          || { echo "MISS: section '$s' lost pre-existing edge to \`$n\` (line was replaced, not extended)"; fail=1; }
      done
      printf '%s\n' "$after_names" | grep -qx "$COMP" \
        || { echo "MISS: section '$s' never gained the owed back-link to \`$COMP\`"; fail=1; }
    done
    ;;
  gate1-parent)
    # Mixed-mode parent containment (I1): the ONLY difference between a mixed parent's
    # before/after may sit inside the given member's own "- **Components:**" field (the
    # Shallow list: reconcile) — nothing else in the parent, including any other member's
    # section, may change. Unlike gate1 there is no new H2 to strip: the member's H2
    # already exists in the parent before onboarding touches it, only its Components:
    # field's shallow list changes.
    BEFORE="${1:?}"; AFTER="${2:?}"; MEMBER="${3:?}"
    A="$(mktemp)"; B="$(mktemp)"; DIFF="$(mktemp)"
    blank_field "$BEFORE" "$FIELD_COMPONENTS" "@@ALLOWED@@" "$MEMBER" > "$A"
    blank_field "$AFTER"  "$FIELD_COMPONENTS" "@@ALLOWED@@" "$MEMBER" > "$B"
    if ! diff -u "$A" "$B" > "$DIFF"; then
      echo "MISS: parent content outside ${MEMBER}'s Components: field differs:"; sed -n '1,40p' "$DIFF"; fail=1
    fi
    rm -f "$A" "$B" "$DIFF"
    ;;
  headings)
    BEFORE="${1:?}"; AFTER="${2:?}"; WANT="${3:?}"
    b="$(grep -cE '^## ' "$BEFORE")"; a="$(grep -cE '^## ' "$AFTER")"
    d=$((a - b))
    [ "$d" = "$WANT" ] || { echo "MISS: heading delta $d, expected $WANT (before=$b after=$a)"; fail=1; }
    ;;
  noop)
    BEFORE="${1:?}"; AFTER="${2:?}"
    if [ ! -e "$AFTER" ]; then :; elif ! diff -q "$BEFORE" "$AFTER" >/dev/null; then
      echo "MISS: a stop path wrote to the index"; diff -u "$BEFORE" "$AFTER" | sed -n '1,20p'; fail=1
    fi
    ;;
  edge)
    IDX="${1:?}"; A="${2:?}"; B="${3:?}"; WANT="${4:-present}"
    afield="$(get_field "$IDX" "$A")"
    bfield="$(get_field "$IDX" "$B")"
    has_token() { # has_token <field-text> <name>
      printf '%s' "$1" | awk -v name="$2" '{ gsub(/[^A-Za-z0-9_-]/, " "); n=split($0,a," "); for(i=1;i<=n;i++) if(a[i]==name) f=1 } END{exit !f}'
    }
    ok=0
    if has_token "$afield" "$B" && has_token "$bfield" "$A"; then ok=1; fi
    if [ "$WANT" = "--absent" ]; then
      [ "$ok" = 1 ] && { echo "MISS: $A<->$B edge present but must NOT be"; fail=1; }
    else
      [ "$ok" = 0 ] && { echo "MISS: $A<->$B edge not on both endpoints"; fail=1; }
    fi
    ;;
  *) echo "unknown mode: $MODE"; exit 2;;
esac

[ "$fail" = 0 ] && echo "ONBOARD-GRADE OK ($MODE)" || echo "ONBOARD-GRADE FAILED ($MODE)"
exit $fail
