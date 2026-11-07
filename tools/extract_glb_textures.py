#!/usr/bin/env python3
"""Extract the backrooms textures embedded in the user-supplied
models/Backrooms.glb into graphics/backrooms/ so LÖVE can load them.

g3d cannot read .glb, so the game builds its rooms from boxes in code and only
uses the wallpaper, carpet and ceiling-tile images from the model. The bytes
are copied unchanged (no re-encoding). Run from the repo root:

    python3 -I tools/extract_glb_textures.py

Re-running it reproduces the committed files byte for byte.
"""
import json
import os
import struct
import sys

GLB = 'models/Backrooms.glb'
OUT_DIR = 'graphics/backrooms'
# glTF material name -> output file stem (extension follows the mime type)
WANTED = {
    'Backrooms Wallpaper': 'wall',
    'Floor': 'floor',
    'Porcelain Tiles': 'ceiling',
}


def main():
    with open(GLB, 'rb') as f:
        data = f.read()
    magic, version, _ = struct.unpack('<4sII', data[:12])
    if magic != b'glTF' or version != 2:
        sys.exit('not a glTF 2.0 binary: ' + GLB)
    json_len, json_type = struct.unpack('<II', data[12:20])
    if json_type != 0x4E4F534A:
        sys.exit('first chunk is not JSON')
    gltf = json.loads(data[20:20 + json_len])
    off = 20 + json_len
    bin_len, bin_type = struct.unpack('<II', data[off:off + 8])
    if bin_type != 0x004E4942:
        sys.exit('second chunk is not BIN')
    blob = data[off + 8:off + 8 + bin_len]

    os.makedirs(OUT_DIR, exist_ok=True)
    found = set()
    for mat in gltf['materials']:
        stem = WANTED.get(mat['name'])
        if not stem:
            continue
        tex_index = mat['pbrMetallicRoughness']['baseColorTexture']['index']
        image = gltf['images'][gltf['textures'][tex_index]['source']]
        view = gltf['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        payload = blob[start:start + view['byteLength']]
        ext = {'image/jpeg': 'jpg', 'image/png': 'png'}[image['mimeType']]
        path = os.path.join(OUT_DIR, stem + '.' + ext)
        with open(path, 'wb') as out:
            out.write(payload)
        print('%s <- material %r image %r (%d bytes)' % (path, mat['name'], image.get('name'), len(payload)))
        found.add(mat['name'])
    missing = set(WANTED) - found
    if missing:
        sys.exit('materials not found in %s: %s' % (GLB, ', '.join(sorted(missing))))


if __name__ == '__main__':
    main()
