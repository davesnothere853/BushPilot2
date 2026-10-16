# Bush Pilot 2: turn the Mixamo pilot into polyart for the game, KEEPING his
# skeleton and skin weights so every Mixamo animation still drives him.
#   python3 tools/polyart_pilot.py <src.fbx> <out.fbx> [ratio]
# Decimate (collapse) -> flat facets -> one shared palette (texture sampled
# per face, k-means) -> vertex colours. The hard hat goes (as before); the
# hi-vis vest becomes a brown leather flight vest.
import bpy, numpy as np, sys
from collections import Counter
args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
SRC, OUT = args[0], args[1]
RATIO = float(args[2]) if len(args) > 2 else 0.06
COLOURS = 14

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in list(meshes):
    if o.name.endswith('Helmet'):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']

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

total0 = sum(len(o.data.polygons) for o in meshes)
per = []
for o in meshes:
    img = image_of(o)
    # Decimate first in the stack, so the armature keeps driving the result.
    ratio = RATIO * (2.2 if ('Eyelash' in o.name or 'Hair' in o.name) else 1.0)
    d = o.modifiers.new('Decimate', 'DECIMATE')
    d.ratio = ratio
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    while o.modifiers[0].name != 'Decimate':
        bpy.ops.object.modifier_move_up(modifier='Decimate')
    bpy.ops.object.modifier_apply(modifier='Decimate')
    me = o.data
    uv = me.uv_layers.active.data if me.uv_layers.active else None
    cols = []
    for p in me.polygons:
        p.use_smooth = False
        if img is None or uv is None:
            cols.append(np.array([0.3, 0.3, 0.3])); continue
        px, w, h = pixels(img)
        us = [uv[li].uv[0] for li in p.loop_indices]
        vs = [uv[li].uv[1] for li in p.loop_indices]
        mu, mv = sum(us) / len(us), sum(vs) / len(vs)
        smp = []
        for t in (0.0, 0.33, 0.66):
            u = mu * (1 - t) + us[0] * t
            v = mv * (1 - t) + vs[0] * t
            smp.append(px[int((v % 1.0) * (h - 1)), int((u % 1.0) * (w - 1)), :3])
        c = np.power(np.clip(np.median(np.array(smp), axis=0), 0, 1), 2.2)
        if o.name.endswith('Vest'):
            # Leather: keep the light and shade of the sample, lose the hi-vis.
            lum = float(np.dot(c, [0.3, 0.55, 0.15]))
            c = np.array([0.30, 0.165, 0.085]) * (0.55 + 0.9 * min(lum, 0.6))
        cols.append(c)
    per.append((o, cols))

allc = np.sqrt(np.array([c for _, cs in per for c in cs]))
rng = np.random.default_rng(1)
cent = allc[rng.choice(len(allc), COLOURS, replace=False)]
for _ in range(30):
    lab = np.argmin(((allc[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
    for k in range(COLOURS):
        if (lab == k).any():
            cent[k] = allc[lab == k].mean(0)

mat = bpy.data.materials.new('PilotPolyart')
mat.use_nodes = True
nt = mat.node_tree
bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
vc = nt.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'Col'
nt.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
for o, cs in per:
    me = o.data
    lab = [int(np.argmin(((cent - np.sqrt(c)) ** 2).sum(-1))) for c in cs]
    ef = {}
    for p in me.polygons:
        for ek in p.edge_keys:
            ef.setdefault(ek, []).append(p.index)
    new = list(lab)
    for p in me.polygons:
        nb = [f for ek in p.edge_keys for f in ef[ek] if f != p.index]
        if nb:
            cnt = Counter(lab[f] for f in nb)
            best, num = cnt.most_common(1)[0]
            if best != lab[p.index] and num >= 2 and cnt.get(lab[p.index], 0) == 0:
                new[p.index] = best
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    ca = me.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
    for p in me.polygons:
        q = cent[new[p.index]] ** 2
        jit = 1.0 + ((p.index * 7919) % 100 - 50) / 1400.0
        srgb = [min(max(v * jit, 0.0), 1.0) ** (1 / 2.2) for v in q]
        for li in p.loop_indices:
            ca.data[li].color_srgb = (srgb[0], srgb[1], srgb[2], 1.0) if hasattr(ca.data[li], 'color_srgb') else (q[0], q[1], q[2], 1.0)
    me.materials.clear()
    me.materials.append(mat)

total1 = sum(len(o.data.polygons) for o in meshes)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(filepath=OUT, use_selection=False, add_leaf_bones=False,
    bake_anim=False, mesh_smooth_type='FACE', colors_type='SRGB',
    use_armature_deform_only=False, path_mode='STRIP')
print('POLYART PILOT faces %d -> %d, %d colours, saved %s' % (total0, total1, COLOURS, OUT))
