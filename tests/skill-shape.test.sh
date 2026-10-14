#!/usr/bin/env bash
# Shape gate for skills/bootstrap/SKILL.md: monorepo/mixed PROCEDURE does not live inline.
#
# WHY. Every bootstrap run reads the whole SKILL.md, and multi-repo is the common case, so any
# monorepo- or mixed-only prose in it is pure cost on that run (measured 2026-10-14: ~150 of
# 536 lines). That procedure lives in references/bootstrap-monorepo-mixed.md, which Step 1
# loads only when detect-mode.sh reports mode=monorepo or mode=mixed.
#
# EXEMPT ON PURPOSE: the Safety boundary and Common mistakes sections. Write-safety rules —
# host-at-root, never in-place, never `git add` — must never depend on a conditional load
# happening. They stay in SKILL.md even though some are mixed-specific.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../skills/bootstrap/SKILL.md"
R="$HERE/../references/bootstrap-monorepo-mixed.md"
fail=0
miss() { echo "  MISS  $1"; fail=1; }
ok()   { echo "  PASS  $1"; }

section() { # section <file> <heading-regex> -> that ## section's body (until the next ## heading)
  awk -v re="$2" '/^## /{ins = ($0 ~ re)} ins' "$1"
}

# 1. no mode-specific paragraph outside the exempt sections
hits="$(awk '
  /^## /{ exempt = ($0 ~ /^## (Safety boundary|Common mistakes)/) }
  !exempt && /^(- )?\*\*(Monorepo|Mixed)( mode)?|^### Mixed mode/ { print NR": "$0 }' "$S")"
[ -z "$hits" ] && ok "no Monorepo/Mixed procedure paragraphs inline (outside Safety/Common mistakes)" \
  || { miss "mode-specific paragraphs still inline:"; printf '%s\n' "$hits" | sed 's/^/          /'; }

# 2. the reference exists and is where the procedure went
[ -f "$R" ] && ok "references/bootstrap-monorepo-mixed.md exists" || miss "references/bootstrap-monorepo-mixed.md missing"

# 3. Step 1 routes BOTH modes to it, by its ${CLAUDE_PLUGIN_ROOT} path
step1="$(section "$S" '^## Step 1')"
for m in monorepo mixed; do
  printf '%s\n' "$step1" | awk -v m="$m" '$0 ~ "^- \\*\\*`mode="m"`" {inb=1} inb && /^- \*\*`mode=/ && $0 !~ "mode="m {inb=0} inb' \
    | grep -qF '${CLAUDE_PLUGIN_ROOT}/references/bootstrap-monorepo-mixed.md' \
    && ok "Step 1's mode=$m route loads the reference" || miss "Step 1's mode=$m route does not load the reference"
done

# 4. component-detection.md is not read unconditionally in Step 0 (a multi-repo run never needs it)
section "$S" '^## Step 0' | grep -q 'component-detection\.md' \
  && miss "Step 0 still reads component-detection.md unconditionally" || ok "Step 0 no longer reads component-detection.md"
[ -f "$R" ] && grep -q 'component-detection\.md' "$R" && ok "the reference tells monorepo/mixed runs to read component-detection.md" \
  || miss "nothing tells a monorepo/mixed run to read component-detection.md"

# 5. the Safety boundary still carries its mixed-mode write rules (must NOT have moved)
safety="$(section "$S" '^## Safety boundary')"
for phrase in 'host-at-root' 'in-place' 'git add'; do
  printf '%s\n' "$safety" | grep -qi -- "$phrase" && ok "Safety boundary still states: $phrase" || miss "Safety boundary lost: $phrase"
done

echo
[ "$fail" = 0 ] && echo "SKILL SHAPE OK" || echo "SKILL SHAPE FAILED"
exit $fail
