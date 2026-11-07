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

step "package: sh tools/package.sh (reproducible .love)"
sh tools/package.sh > /tmp/check_pkg1.txt 2>&1 || fail=1
sh tools/package.sh > /tmp/check_pkg2.txt 2>&1 || fail=1
cat /tmp/check_pkg2.txt
h1=$(grep 'dist/not-how-it-works.love$' /tmp/check_pkg1.txt | cut -d' ' -f1)
h2=$(grep 'dist/not-how-it-works.love$' /tmp/check_pkg2.txt | cut -d' ' -f1)
if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then echo "ok (two builds, same sha256)"; else echo "FAIL (sha256 differs: $h1 / $h2)"; fail=1; fi
ART="$(pwd)/dist/not-how-it-works.love"
python3 -I -c "
import sys, zipfile
n = zipfile.ZipFile(sys.argv[1]).namelist()
bad = [x for x in n if x.startswith(('.git', '.claude', 'openspec/', 'dist/', 'tools/', 'models/')) or (x.startswith('tests/') and x != 'tests/autotest.lua') or '__pycache__' in x]
ok = 'main.lua' in n and 'conf.lua' in n and 'THIRD_PARTY_NOTICES.md' in n
print('ok (main.lua at root, %d files, no dev-only files)' % len(n) if ok and not bad else 'FAIL contents: missing root files or %s' % bad)
sys.exit(0 if ok and not bad else 1)
" "$ART" || fail=1

for mode in "" "--placeholder-assets"; do
    step "artifact launch, 8 s: love dist/not-how-it-works.love $mode (run from /tmp)"
    (cd /tmp && xvfb-run -a timeout 8 love "$ART" $mode) > /tmp/check_pkg_launch.txt 2>&1
    code=$?
    if [ $code -ne 124 ] || grep -q 'Error' /tmp/check_pkg_launch.txt; then
        echo "FAIL (exit $code)"; cat /tmp/check_pkg_launch.txt; fail=1
    else echo "ok (still running after 8 s, no errors logged)"; fi

    step "artifact playthrough: love dist/not-how-it-works.love --autotest $mode"
    (cd /tmp && AUTOTEST_OUT="/tmp/autotest-artifact${mode}" xvfb-run -a -s '-screen 0 1024x1024x24' timeout 300 \
        love "$ART" --autotest $mode) > /tmp/check_pkg_autotest.txt 2>&1 || fail=1
    grep -E 'FAIL|ERROR|checks,' /tmp/check_pkg_autotest.txt
done

step "artifact playthrough with the debug opt-in: love dist/not-how-it-works.love --autotest --debug"
(cd /tmp && AUTOTEST_OUT="/tmp/autotest-artifact--debug" xvfb-run -a -s '-screen 0 1024x1024x24' timeout 300 \
    love "$ART" --autotest --debug) > /tmp/check_pkg_autotest_debug.txt 2>&1 || fail=1
grep -E 'FAIL|ERROR|debug|checks,' /tmp/check_pkg_autotest_debug.txt

echo
if [ $fail -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $fail
