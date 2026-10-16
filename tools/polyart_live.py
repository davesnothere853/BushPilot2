# Polyart palette pass, run inside Blender on the open pilot:
#   exec(open(r'C:\Users\davku\Documents\BushPilot2\tools\polyart_live.py').read())
# Saves a backup first, applies Decimate, then swaps photo textures for
# one shared palette of flat colours (one colour per facet), with a cleanup
# pass that removes lone speckle facets.
import bpy, numpy as np
from collections import Counter
D = bpy.data
C = bpy.context
COLOURS = 14

bpy.ops.wm.save_as_mainfile(filepath=r'C:\Users\davku\Documents\BushPilot2\reference\pilot_before_palette.blend', copy=True)
if C.object and C.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
meshes = [o for o in D.objects if o.type == 'MESH']

for o in meshes:
    if 'Decimate' in o.modifiers:
        with C.temp_override(object=o, active_object=o, selected_objects=[o], selected_editable_objects=[o]):
            bpy.ops.object.modifier_apply(modifier='Decimate')

def image_of(o):
    for m in o.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image and n.image.size[0] > 0:
                    return n.image
    return None

_cache = {}
def pixels(img):
    if img.name not in _cache:
        w, h = img.size
        a = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(a)
        _cache[img.name] = (a.reshape(h, w, 4), w, h)
    return _cache[img.name]

per_mesh = []
for o in meshes:
    me = o.data
    img = image_of(o)
    uv = me.uv_layers.active.data if me.uv_layers.active else None
    cols = []
    for p in me.polygons:
        p.use_smooth = False
        if img is None or uv is None:
            cols.append(np.array([0.3, 0.3, 0.3]))
            continue
        px, w, h = pixels(img)
        us = [uv[li].uv[0] for li in p.loop_indices]
        vs = [uv[li].uv[1] for li in p.loop_indices]
        mu, mv = sum(us) / len(us), sum(vs) / len(vs)
        samples = []
        for t in (0.0, 0.33, 0.66):
            u = mu * (1 - t) + us[0] * t
            v = mv * (1 - t) + vs[0] * t
            samples.append(px[int((v % 1.0) * (h - 1)), int((u % 1.0) * (w - 1)), :3])
        c = np.median(np.array(samples), axis=0)
        cols.append(np.power(np.clip(c, 0, 1), 2.2))
    per_mesh.append((o, cols))

# One shared palette (k-means in a perceptual-ish space).
allc = np.sqrt(np.array([c for _, cs in per_mesh for c in cs]))
rng = np.random.default_rng(1)
cent = allc[rng.choice(len(allc), COLOURS, replace=False)]
for _ in range(30):
    lab = np.argmin(((allc[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
    for k in range(COLOURS):
        if (lab == k).any():
            cent[k] = allc[lab == k].mean(0)

mat = D.materials.get('Polyart') or D.materials.new('Polyart')
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    if n.type not in ('BSDF_PRINCIPLED', 'OUTPUT_MATERIAL'):
        nt.nodes.remove(n)
bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
attr = nt.nodes.new('ShaderNodeVertexColor')
attr.layer_name = 'pal'
nt.links.new(attr.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 0.85

for o, cs in per_mesh:
    me = o.data
    lab = [int(np.argmin(((cent - np.sqrt(c)) ** 2).sum(-1))) for c in cs]
    # Cleanup: a facet whose neighbours mostly agree on another colour joins them.
    edge_faces = {}
    for p in me.polygons:
        for ek in p.edge_keys:
            edge_faces.setdefault(ek, []).append(p.index)
    new = list(lab)
    for p in me.polygons:
        nb = [f for ek in p.edge_keys for f in edge_faces[ek] if f != p.index]
        if not nb:
            continue
        cnt = Counter(lab[f] for f in nb)
        best, num = cnt.most_common(1)[0]
        if best != lab[p.index] and num >= 2 and cnt.get(lab[p.index], 0) == 0:
            new[p.index] = best
    if 'pal' in me.color_attributes:
        me.color_attributes.remove(me.color_attributes['pal'])
    ca = me.color_attributes.new('pal', 'FLOAT_COLOR', 'CORNER')
    for p in me.polygons:
        q = cent[new[p.index]] ** 2
        jit = 1.0 + ((p.index * 7919) % 100 - 50) / 1400.0
        for li in p.loop_indices:
            ca.data[li].color = (q[0] * jit, q[1] * jit, q[2] * jit, 1.0)
    me.color_attributes.active_color = ca
    me.materials.clear()
    me.materials.append(mat)

print('POLYART DONE:', sum(len(o.data.polygons) for o in meshes), 'faces,', COLOURS, 'colours. Backup saved: reference/pilot_before_palette.blend')
