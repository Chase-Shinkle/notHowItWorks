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

step "generated-level physical sweep (tests/levels_sweep.sh: seeds 1..70 x difficulties 1-3 = 210 levels, ~20 min on 8 cores)"
sh tests/levels_sweep.sh 1 70 > /tmp/check_sweep.txt 2>&1 || fail=1
tail -12 /tmp/check_sweep.txt

step "maze layout dump (tests/maze_layout.lua): ASCII + PNG for review, generation only, no assertions"
MAZE_SEEDS=1,2 MAZE_DIFFS=1,2,3 MAZE_OUT=/tmp/check_maze xvfb-run -a love tests/love_runner tests/maze_layout.lua > /tmp/check_maze.txt 2>&1 || fail=1
tail -1 /tmp/check_maze.txt

# Dedicated maze test files from the parallel branches (branch plots, refund, checkpoints,
# scaling). All four are merged; a missing file fails the run.
for t in maze_branches maze_refund maze_checkpoints maze_scaling zones_lighting zones_shapes zones_audio zones_dressing ui_found ui_title; do
    step "tests/$t.lua"
    if [ ! -f "tests/$t.lua" ]; then echo "FAIL (tests/$t.lua is missing)"; fail=1; continue; fi
    love tests/love_runner "tests/$t.lua" > "/tmp/check_$t.txt" 2>&1 || fail=1
    grep -E '^FAIL|^ERROR|error' "/tmp/check_$t.txt"; tail -1 "/tmp/check_$t.txt"
done

step "pit-rim measurement (tests/rim.lua): pit plots plantable over >= 2.5 m of floor"
love tests/love_runner tests/rim.lua > /tmp/check_rim.txt 2>&1 || fail=1
grep -E '^room|FAIL|rim:' /tmp/check_rim.txt

step "backrooms look fallback ladder (tests/backrooms_review.sh fallback): bad shader == --no-shader, bad post differs, no ERROR"
sh tests/backrooms_review.sh fallback /tmp/check_fallback > /tmp/check_fallback.txt 2>&1 || fail=1
grep -E 'FAILED|ERROR|^DIFF .*noshader' /tmp/check_fallback.txt && fail=1
n_same=$(grep -c '^same .*noshader' /tmp/check_fallback.txt); n_diff=$(grep -c '^DIFF .*badpost' /tmp/check_fallback.txt)
if [ "$n_same" = 3 ] && [ "$n_diff" = 3 ]; then echo "ok (badshader == noshader x3, badpost != full x3)"; else echo "FAIL (same=$n_same diff=$n_diff)"; fail=1; fi

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
    AUTOTEST_OUT="/tmp/autotest${mode}" xvfb-run -a -s '-screen 0 1024x1024x24' timeout 600 \
        love . --autotest $mode > /tmp/check_autotest.txt 2>&1 || fail=1
    grep -E 'FAIL|ERROR|checks,|LEVEL-TIME' /tmp/check_autotest.txt
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
