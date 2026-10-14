#!/usr/bin/env bash
# Durable runtime safety test for scripts/detect-mode.sh. Pure bash, no external deps,
# NEVER invokes git (fixtures that need a real `.git` FILE are materialized at runtime
# via a plain `printf`, never `git init`/`git worktree`, so this stays git-free like the
# script it tests). Ephemeral fixtures live under a mktemp dir, cleaned up on exit.
#
# Cases:
#   (a) M3 containment       — escaping-glob output has no /etc, no ..
#   (b) H4 symlink no-hang   — symlink-cycle terminates under a watchdog
#   (c) L1 .git-file member  — a dir with ONLY a .git FILE (no CLAUDE.md) is a unit repo
#   (d) walk-up POSITIVE     — root CLAUDE.md + 2 member repos -> walk-up fires, root=ws
#   (e) walk-up NEGATIVE     — no root CLAUDE.md + 2 member repos -> root stays at member
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/detect-mode.sh"
FIXTURES="$HERE/fixtures/hostile"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

# --- (a) M3 containment: escaping-glob must never leak /etc or .. into output ---
# (rc not gated on: detect-mode.sh's exit status is tied to whether the trailing `grep
# -E '^unit '` finds any lines, not to success/failure of the detection itself.)
out_a="$(bash "$SCRIPT" "$FIXTURES/escaping-glob" 2>&1)"
if printf '%s\n' "$out_a" | grep -qE '/etc|\.\.'; then
  fail "(a) M3 containment: output leaked /etc or .. -- $out_a"
fi

# --- (b) H4 symlink no-hang: run under a manual watchdog, kill+FAIL if still running after ~10s ---
bash "$SCRIPT" "$FIXTURES/symlink-cycle" > "$TMP/b.out" 2>&1 &
b_pid=$!
b_done=0
for _ in $(seq 1 100); do
  if ! kill -0 "$b_pid" 2>/dev/null; then b_done=1; break; fi
  sleep 0.1
done
if [ "$b_done" != 1 ]; then
  kill -9 "$b_pid" 2>/dev/null
  wait "$b_pid" 2>/dev/null
  fail "(b) H4 symlink-cycle: detect-mode.sh did not terminate within ~10s"
fi
wait "$b_pid" 2>/dev/null
# rc is not asserted here: an ambiguous-mode run with zero `unit` lines legitimately exits
# 1 (the trailing `grep -E '^unit '` finds nothing) — that's pre-existing, unrelated to H4.
# The only thing under test is that the run TERMINATES rather than hanging on the symlink.

# --- (c) L1 .git-file member, genuinely exercised: ONLY a .git FILE, no CLAUDE.md ---
c_ws="$TMP/gitfile-ws"
mkdir -p "$c_ws/member"
printf 'gitdir: /nonexistent\n' > "$c_ws/member/.git"
out_c="$(bash "$SCRIPT" "$c_ws" 2>&1)"
printf '%s\n' "$out_c" | grep -q '^unit repo member$' \
  || fail "(c) L1 .git-file: expected 'unit repo member', got: $out_c"

# --- (d) walk-up POSITIVE: root CLAUDE.md + 2 member repos -> root resolves to ws, mode=multi-repo ---
d_ws="$TMP/walkup-pos/ws"
mkdir -p "$d_ws/member-a" "$d_ws/member-b"
printf '# root\n' > "$d_ws/CLAUDE.md"
printf 'gitdir: /x/a.git\n' > "$d_ws/member-a/.git"   # a member REPO: only .git marks one
printf 'gitdir: /x/b.git\n' > "$d_ws/member-b/.git"
out_d="$(bash "$SCRIPT" "$d_ws/member-a" 2>&1)"
d_root="$(printf '%s\n' "$out_d" | grep -E '^root=' | sed 's/^root=//')"
d_mode="$(printf '%s\n' "$out_d" | grep -E '^mode=' | sed 's/^mode=//')"
d_ws_real="$(cd "$d_ws" && pwd)"
[ "$d_root" = "$d_ws_real" ] || fail "(d) walk-up positive: root=$d_root, expected $d_ws_real"
[ "$d_mode" = "multi-repo" ] || fail "(d) walk-up positive: mode=$d_mode, expected multi-repo"

# --- (e) walk-up NEGATIVE (the fix): NO root CLAUDE.md + 2 member repos -> root stays at member-a ---
e_ws="$TMP/walkup-neg/gen"
mkdir -p "$e_ws/member-a" "$e_ws/member-b"
printf 'gitdir: /x/a.git\n' > "$e_ws/member-a/.git"   # a member REPO: only .git marks one
printf 'gitdir: /x/b.git\n' > "$e_ws/member-b/.git"
out_e="$(bash "$SCRIPT" "$e_ws/member-a" 2>&1)"
e_root="$(printf '%s\n' "$out_e" | grep -E '^root=' | sed 's/^root=//')"
e_member_real="$(cd "$e_ws/member-a" && pwd)"
[ "$e_root" = "$e_member_real" ] || fail "(e) walk-up negative: root=$e_root, expected it to stay at $e_member_real (fail-closed)"

echo "SAFETY OK"
exit 0
