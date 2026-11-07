#!/bin/sh
# Runs every automated check on the real LÖVE 11.5 runtime. From the repo root:
#   sh tests/check_all.sh
# Needs `love` on PATH and xvfb-run (for the windowed checks).
set -u
fail=0
step() { echo; echo "== $*"; }

step "unit/headless tests (tests/run.lua, LÖVE's LuaJIT, mocked LÖVE API)"
love tests/love_runner tests/run.lua > /tmp/check_run.txt 2>&1 || fail=1
grep '^FAIL' -A1 /tmp/check_run.txt; tail -1 /tmp/check_run.txt

step "reachability sweep (tests/reachability.lua)"
love tests/love_runner tests/reachability.lua > /tmp/check_reach.txt 2>&1 || fail=1
grep -v '^ok ' /tmp/check_reach.txt | tail -5

for mode in "" "--placeholder-assets"; do
    step "plain launch, 8 s: love . $mode"
    xvfb-run -a timeout 8 love . $mode > /tmp/check_launch.txt 2>&1
    code=$?
    # LÖVE's error screen keeps the window open (timeout -> 124) and prints
    # "Error: ..." to stdout, so the log is checked, not just the exit code.
    if [ $code -ne 124 ] || grep -q 'Error' /tmp/check_launch.txt; then
        echo "FAIL (exit $code)"; cat /tmp/check_launch.txt; fail=1
    else echo "ok (still running after 8 s, no errors logged)"; fi

    step "scripted playthrough: love . --autotest $mode"
    AUTOTEST_OUT="/tmp/autotest${mode}" xvfb-run -a -s '-screen 0 1024x1024x24' timeout 300 \
        love . --autotest $mode > /tmp/check_autotest.txt 2>&1 || fail=1
    grep -E 'FAIL|ERROR|checks,' /tmp/check_autotest.txt
done

echo
if [ $fail -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $fail
