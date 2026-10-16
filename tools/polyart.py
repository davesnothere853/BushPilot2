import bpy, numpy as np, math, sys
OUT = sys.argv[-1]
SRC = '/home/claude/bushpilot/assets/characters/src/'
bpy.ops.wm.read_factory_settings(use_empty=True)

def import_char(offset_x):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=SRC + 'Ch17_nonPBR.fbx')
    objs = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in objs if o.type == 'ARMATURE'][0]
    return arm, [o for o in objs if o.type == 'MESH']

def pose_idle(arm):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=SRC + 'idle.fbx')
    new = [o for o in bpy.data.objects if o not in before]
    src_arm = [o for o in new if o.type == 'ARMATURE'][0]
    act = src_arm.animation_data.action
    arm.animation_data_create()
    arm.animation_data.action = act
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.scene.frame_set(20)

def bake_pose(meshes):
    for m in meshes:
        bpy.context.view_layer.objects.active = m
        for mod in list(m.modifiers):
            if mod.type == 'ARMATURE':
                bpy.ops.object.modifier_apply(modifier=mod.name)

def image_of(mesh):
    mat = mesh.data.materials[0]
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            return n.image
    return None

_cache = {}
def pixels(img):
    if img.name not in _cache:
        w, h = img.size
        _cache[img.name] = (np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4), w, h)
    return _cache[img.name]

def polyart(meshes, ratio):
    face_cols = []
    for m in meshes:
        dec = m.modifiers.new('dec', 'DECIMATE')
        dec.ratio = ratio
        bpy.context.view_layer.objects.active = m
        bpy.ops.object.modifier_apply(modifier='dec')
        img = image_of(m)
        me = m.data
        uv = me.uv_layers.active.data
        cols = []
        for p in me.polygons:
            if img is None:
                cols.append((0.3, 0.3, 0.3)); continue
            px, w, h = pixels(img)
            # Average a few samples across the face so a facet gets its true colour.
            us = [uv[li].uv[0] for li in p.loop_indices]
            vs = [uv[li].uv[1] for li in p.loop_indices]
            samples = []
            for t in (0.0, 0.33, 0.66):
                u = sum(us) / len(us) * (1 - t) + us[0] * t
                v = sum(vs) / len(vs) * (1 - t) + vs[0] * t
                samples.append(px[int((v % 1.0) * (h - 1)), int((u % 1.0) * (w - 1)), :3])
            c = np.median(np.array(samples), axis=0)
            cols.append(tuple(np.power(np.clip(c, 0, 1), 2.2)))
            p.use_smooth = False
        face_cols.append((m, cols))
    # One shared small palette for the whole character (k-means, 9 colours).
    allc = np.sqrt(np.array([c for _, cs in face_cols for c in cs]))
    rng = np.random.default_rng(1)
    cent = allc[rng.choice(len(allc), 14, replace=False)]
    for _ in range(25):
        lab = np.argmin(((allc[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
        for k in range(len(cent)):
            if (lab == k).any():
                cent[k] = allc[lab == k].mean(0)
    mat = bpy.data.materials.new('Polyart')
    mat.use_nodes = True
    nt = mat.node_tree
    attr = nt.nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'pal'
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 0.85
    nt.links.new(attr.outputs['Color'], bsdf.inputs['Base Color'])
    i = 0
    for m, cs in face_cols:
        me = m.data
        ca = me.color_attributes.new('pal', 'FLOAT_COLOR', 'CORNER')
        for p, c in zip(me.polygons, cs):
            k = np.argmin(((cent - np.sqrt(np.array(c))) ** 2).sum(-1))
            q = cent[k] ** 2
            # A touch of per-facet variation, like hand-painted polyart.
            jit = 1.0 + (hash((p.index, m.name)) % 100 - 50) / 1400.0
            for li in p.loop_indices:
                ca.data[li].color = (q[0] * jit, q[1] * jit, q[2] * jit, 1.0)
        me.materials.clear()
        me.materials.append(mat)
    return sum(len(m.data.polygons) for m in meshes)

# Before (original) and after (polyart), side by side.
armA, meshA = import_char(0)
pose_idle(armA)
armB, meshB = import_char(0)
armB.animation_data_create()
armB.animation_data.action = armA.animation_data.action
bpy.context.scene.frame_set(20)
bake_pose(meshA); bake_pose(meshB)
for o in [armA] + meshA:
    o.location.x -= 0.65 if o.type == 'ARMATURE' else 0
for o in [armB] + meshB:
    o.location.x += 0.65 if o.type == 'ARMATURE' else 0
for m in meshA:
    m.location.x -= 0.65
for m in meshB:
    m.location.x += 0.65
orig = sum(len(m.data.polygons) for m in meshA)
n = polyart(meshB, 0.06)
print('FACES before', orig, 'after', n)

# Simple stage: grassy ground, low warm sun, blue sky.
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
g = bpy.context.object
gm = bpy.data.materials.new('g'); gm.use_nodes = True
gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.13, 0.22, 0.06, 1)
gm.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.95
g.data.materials.append(gm)
sun = bpy.data.lights.new('sun', 'SUN'); sun.energy = 3.2; sun.color = (1.0, 0.9, 0.78)
so = bpy.data.objects.new('sun', sun); bpy.context.collection.objects.link(so)
so.rotation_euler = (math.radians(55), 0, math.radians(-35))
w = bpy.data.worlds.new('w'); bpy.context.scene.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.42, 0.58, 0.85, 1)
w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.7
cam = bpy.data.cameras.new('cam'); cam.lens = 50
co = bpy.data.objects.new('cam', cam); bpy.context.collection.objects.link(co)
co.location = (0, -4.6, 1.25); co.rotation_euler = (math.radians(88), 0, 0)
sc = bpy.context.scene; sc.camera = co
sc.render.engine = 'CYCLES'; sc.cycles.samples = 48; sc.cycles.device = 'CPU'
sc.render.resolution_x = 1280; sc.render.resolution_y = 900
sc.view_settings.view_transform = 'AgX'
sc.render.filepath = OUT + '/pilot_before_after.png'
bpy.ops.render.render(write_still=True)
# Keep the polyart pilot as a file the game can use.
bpy.ops.object.select_all(action='DESELECT')
for o in [armB] + meshB:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT + '/pilot_polyart.glb', use_selection=True, export_apply=True)
print('DONE')
