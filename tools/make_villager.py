#!/usr/bin/env python3
"""Makes the farm villager sprite from the hero sprite (dev-time only).

    python3 -I tools/make_villager.py         (from anywhere inside the repo)

Needs Pillow. Reads the hero sprite from the farm pack, recolours the hair
(purple -> brown) and the sleeves (red -> green), paints a straw hat over the
top of the head and a cream apron over the torso, and writes
graphics/characters/villager.png at the same 13x16 size, so the player and the
villager are told apart in a screenshot without any draw-time tint. The
output is committed like the other art; re-running gives the same pixels.
"""
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
HERO = os.path.join(ROOT, 'graphics', 'Farming - Crops Pack 017', 'Sprites', 'Hero  white - 001 copy.png')
OUT = os.path.join(ROOT, 'graphics', 'characters', 'villager.png')

OUTLINE = (11, 20, 30, 255)

# hero palette entry -> villager colour
RECOLOR = {
    (91, 31, 147, 255): (92, 52, 28, 255),      # hair shadow  -> dark brown
    (139, 69, 206, 255): (150, 92, 48, 255),    # hair         -> brown
    (230, 161, 242, 255): (214, 162, 96, 255),  # hair light   -> light brown
    (198, 33, 77, 255): (62, 128, 72, 255),     # sleeves      -> green
    (206, 59, 122, 255): (92, 160, 92, 255),    # sleeve light -> light green
}

STRAW = (226, 190, 98, 255)
STRAW_DARK = (176, 132, 58, 255)
BAND = (170, 48, 40, 255)
APRON = (241, 233, 212, 255)
APRON_DARK = (205, 193, 168, 255)

# Hat over rows 0-3: crown (rows 0-1), band (row 2) and a wide brim (row 3). '#' outline,
# 's' straw, 'd' dark straw, 'b' band, '.' leave the hero pixel.
HAT = [
    '...#######...',
    '..#sssssss#..',
    '#dbbbbbbbbbd#',
    '#sssssssssss#',
]
HAT_COLORS = {'#': OUTLINE, 's': STRAW, 'd': STRAW_DARK, 'b': BAND}

# Apron over the torso (rows 9-13, columns 3-9): bib, waist and skirt.
APRON_ROWS = {
    9: (5, 7, 'a'),
    10: (4, 8, 'a'),
    11: (4, 8, 'a'),
    12: (4, 8, 'a'),
    13: (4, 8, 'h'),
}


def main():
    hero = Image.open(HERO).convert('RGBA')
    out = hero.copy()
    w, h = out.size
    px = out.load()
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p in RECOLOR:
                px[x, y] = RECOLOR[p]
    for y, row in enumerate(HAT):
        for x, c in enumerate(row):
            if c in HAT_COLORS:
                px[x, y] = HAT_COLORS[c]
    for y, (x0, x1, kind) in APRON_ROWS.items():
        for x in range(x0, x1 + 1):
            px[x, y] = APRON_DARK if kind == 'h' or x in (x0, x1) and y > 9 else APRON
    px[6, 11] = APRON_DARK                        # pocket
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print('wrote %s (%dx%d)' % (os.path.relpath(OUT, ROOT), w, h))


if __name__ == '__main__':
    main()
