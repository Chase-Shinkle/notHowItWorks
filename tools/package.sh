#!/bin/sh
# Builds a reproducible .love package: dist/not-how-it-works.love
#
#   sh tools/package.sh            (from anywhere inside the repo)
#
# main.lua and conf.lua sit at the ZIP root. Included: game code (src/),
# libraries (lib/, g3d/ incl. its g3d.vert shader), runtime art (graphics/),
# sounds/ and fonts/ and shaders/ if they exist, the license notices and the
# release notes, and ONLY tests/autotest.lua (the scripted playthrough that
# `love game.love --autotest` runs, so the exact artifact can be verified; it is
# never loaded without that flag). Everything else is left out: .git, .claude,
# openspec/, the other tests and mocks, tools/, dist/, models/Backrooms.glb
# (not loaded at runtime; its textures are already extracted to
# graphics/backrooms/), caches, logs, .DS_Store and any credential-like files.
#
# Reproducible: files are added in sorted order with a fixed timestamp
# (1980-01-01) and fixed permissions, so the same tree gives the same bytes and
# the same sha256.
set -eu
cd "$(dirname "$0")/.."
mkdir -p dist
OUT="dist/not-how-it-works.love"

python3 -I - "$OUT" <<'PY'
import os, sys, zipfile

out = sys.argv[1]
ROOT_FILES = ['main.lua', 'conf.lua', 'THIRD_PARTY_NOTICES.md', 'RELEASE.md']
DIRS = ['src', 'lib', 'g3d', 'graphics', 'sounds', 'fonts', 'shaders']
EXTRA = ['tests/autotest.lua']
SKIP_NAMES = {'.DS_Store', 'Thumbs.db', '__pycache__', '.git'}
SKIP_EXT = ('.pyc', '.log', '.tmp', '.swp', '.bak', '.orig')
SKIP_HINTS = ('secret', 'credential', 'token', '.env', 'id_rsa', '.pem', '.key')

files = []
for f in ROOT_FILES + EXTRA:
    if not os.path.isfile(f):
        sys.exit('missing required file: ' + f)
    files.append(f)
for d in DIRS:
    if not os.path.isdir(d):
        continue
    for base, dirnames, names in os.walk(d):
        dirnames[:] = [n for n in dirnames if n not in SKIP_NAMES and not n.startswith('.')]
        for n in names:
            low = n.lower()
            if n in SKIP_NAMES or n.startswith('.') or low.endswith(SKIP_EXT):
                continue
            if any(h in low for h in SKIP_HINTS):
                sys.exit('refusing to package credential-like file: ' + os.path.join(base, n))
            files.append(os.path.join(base, n).replace(os.sep, '/'))
files = sorted(set(files))

tmp = out + '.tmp'
with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in files:
        info = zipfile.ZipInfo(f, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        info.create_system = 3
        with open(f, 'rb') as fh:
            z.writestr(info, fh.read(), compresslevel=9)
os.replace(tmp, out)
print('%d files -> %s (%d bytes)' % (len(files), out, os.path.getsize(out)))
PY

if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$OUT"
else
    shasum -a 256 "$OUT"
fi
echo "absolute path: $(cd dist && pwd)/$(basename "$OUT")"
