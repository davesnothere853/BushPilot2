# Blender build script (run in the background by tools/blender_run.gd):
# the rock and cliff kit for the gorges (DESIGN_NOTES 235). Each piece is
# modelled the way an artist would - a block, cleaved by fracture planes,
# remeshed, then weathered: rounded edges, fracture cracks, horizontal
# bedding ledges and vertical joints on the cliff faces - and saved as .glb
# into the game. Materials are applied in Godot (triplanar rock + moss).
#   blender -b --factory-startup --python rocks.py -- <out folder>
import bpy, bmesh, math, random, sys, os, time
from mathutils import Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
LOG = open(os.path.join(OUT, "blender_log.txt"), "w")


def log(*a):
    LOG.write(" ".join(str(x) for x in a) + "\n")
    LOG.flush()


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def active(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def apply_mod(ob, m):
    active(ob)
    bpy.ops.object.modifier_apply(modifier=m.name)


def cleave(ob, cuts, rng, lo=0.45, hi=0.9, flat_bottom=True):
    """Fracture planes: slice the block with random planes (the flat faces of a split rock)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    planes = []
    if flat_bottom:
        planes.append((Vector((0, 0, -1)), 0.55))
    for _ in range(cuts):
        n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 1.0))).normalized()
        planes.append((n, rng.uniform(lo, hi)))
    for n, d in planes:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * d, plane_no=n, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bm.to_mesh(me)
    bm.free()


def remesh(ob, voxel):
    m = ob.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    apply_mod(ob, m)


def decimate(ob, tris):
    n = len(ob.data.polygons)
    if n > tris:
        m = ob.modifiers.new("dec", "DECIMATE")
        m.ratio = max(0.02, tris / n)
        apply_mod(ob, m)


def finish(ob, name, bury):
    """Smooth by angle, the base a little below 0 (sits in the ground), export."""
    active(ob)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    except Exception:
        bpy.ops.object.shade_smooth()
    me = ob.data
    zmin = min(v.co.z for v in me.vertices)
    for v in me.vertices:
        v.co.z -= zmin + bury
    me.update()
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_materials="NONE")
    log("wrote", name, len(me.polygons), "tris-ish", "size", tuple(round(x, 2) for x in ob.dimensions))


def weather_rock(ob, size, seed):
    """Rounded, cracked, lumpy: fractal lumps, finer grain, cracks along fracture cells."""
    off = Vector((seed * 17.3, seed * 7.1, seed * 3.7))
    me = ob.data
    me.calc_loop_triangles()
    s = max(size)
    for v in me.vertices:
        p = v.co / s * 2.2 + off
        lump = noise.fractal(p, 0.9, 2.0, 4)
        grain = noise.fractal(p * 5.0, 0.7, 2.2, 3)
        dists, _pts = noise.voronoi(p * 1.6, distance_metric="DISTANCE", exponent=2.5)
        crack = 1.0 - smoothstep(0.0, 0.08, dists[1] - dists[0])
        d = s * (0.07 * lump + 0.018 * grain - 0.035 * crack)
        v.co += v.normal * d
    me.update()


def boulder(name, seed, size, cuts, tris):
    clear()
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0)
    ob = bpy.context.active_object
    ob.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    active(ob)
    bpy.ops.object.transform_apply(scale=True)
    # cleave in the object's own units (planes relative to the half sizes)
    me = ob.data
    for v in me.vertices:
        v.co = Vector((v.co.x / (size[0] * 0.5), v.co.y / (size[1] * 0.5), v.co.z / (size[2] * 0.5)))
    cleave(ob, cuts, rng)
    for v in me.vertices:
        v.co = Vector((v.co.x * size[0] * 0.5, v.co.y * size[1] * 0.5, v.co.z * size[2] * 0.5))
    remesh(ob, max(size) / 70.0)
    weather_rock(ob, size, seed)
    decimate(ob, tris)
    finish(ob, name, max(size) * 0.08)


def cliff(name, seed, W, H, D, tris):
    """A cliff face: a slab of rock, the front cleaved into facets, then bedding
    ledges (horizontal) and joints (vertical) weathered into it."""
    clear()
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_cube_add(size=2.0)
    ob = bpy.context.active_object
    me = ob.data
    # facets across the front and the top
    bm = bmesh.new()
    bm.from_mesh(me)
    for _ in range(5):
        n = Vector((rng.uniform(-0.5, 0.5), 1.0, rng.uniform(-0.3, 0.4))).normalized()     # the face is +Y (Godot -Z, the front)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * rng.uniform(0.55, 0.9), plane_no=n, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    for _ in range(2):
        n = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.2, 0.6), 1.0)).normalized()
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * rng.uniform(0.7, 0.95), plane_no=n, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bm.to_mesh(me)
    bm.free()
    for v in me.vertices:
        v.co = Vector((v.co.x * W * 0.5, v.co.y * D * 0.5, (v.co.z + 1.0) * H * 0.5))
    remesh(ob, min(W, H) / 90.0)
    # round the block off first, so its outline isn't a box
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.factor = 1.0
    sm.iterations = 25
    apply_mod(ob, sm)
    off = Vector((seed * 11.0, seed * 5.0, seed * 2.0))
    layer = rng.uniform(1.6, 3.2)                 # mean bedding thickness (m)
    dip = rng.uniform(-0.18, 0.18)                # the beds tilt across the face
    me.update()
    for v in me.vertices:
        nrm = v.normal
        if nrm.z < -0.6:
            continue
        x, y, z = v.co
        # the beds: warped, tilted, each its own thickness and how far its lip sticks out
        zz = z + dip * x + 1.8 * noise.fractal(Vector((x * 0.025, y * 0.025, 0.0)) + off, 0.8, 2.0, 3)
        bed = math.floor(zz / layer)
        bn = noise.noise(Vector((bed * 0.37, 0.5, 0.5)) + off)
        t = (zz / layer + 0.35 * bn) % 1.0
        amp = 0.35 + 0.9 * (bn * 0.5 + 0.5)
        ledge = (smoothstep(0.0, 0.12 + 0.2 * (bn * 0.5 + 0.5), t) - 0.5) * amp
        # vertical joints: the face breaks into columns and blocks
        dists, _ = noise.voronoi(Vector((x * 0.07, z * 0.025, y * 0.07)) + off, distance_metric="DISTANCE", exponent=2.0)
        joint = 1.0 - smoothstep(0.0, 0.4, dists[1] - dists[0])
        block = noise.noise(Vector((x * 0.07, z * 0.025, y * 0.07)) * 1.0 + off * 1.3)       # whole blocks stand proud or sit back
        big = noise.fractal(Vector((x, y, z)) * 0.035 + off, 0.9, 2.0, 3)
        mid = noise.fractal(Vector((x, y, z)) * 0.11 + off, 0.8, 2.0, 3)
        grain = noise.fractal(Vector((x, y, z)) * 0.5 + off, 0.7, 2.0, 3)
        face = smoothstep(0.1, 0.8, nrm.y)                     # the front face gets the beds and joints
        d = 2.0 * big + 0.6 * mid + 0.1 * grain + face * (0.8 * ledge - 0.8 * joint + 0.6 * block)
        v.co += nrm * d
    me.update()
    # relax any folds the displacement made before thinning the mesh
    sm2 = ob.modifiers.new("relax", "SMOOTH")
    sm2.factor = 0.5
    sm2.iterations = 2
    apply_mod(ob, sm2)
    decimate(ob, tris)
    finish(ob, name, 1.0)


t0 = time.time()
log("rock kit start", bpy.app.version_string)
try:
    ONLY_CLIFFS = "cliffs" in sys.argv
    for i, (sz, cuts) in enumerate([] if ONLY_CLIFFS else [((1.4, 1.1, 0.9), 3), ((2.2, 1.6, 1.3), 4), ((3.2, 2.4, 1.8), 4), ((1.0, 0.9, 0.8), 2), ((2.8, 1.5, 2.0), 5), ((4.0, 3.0, 2.2), 5)]):
        boulder("boulder_%d" % i, 100 + i, sz, cuts, 2600)
    for i, sz in enumerate([] if ONLY_CLIFFS else [(6.0, 4.5, 3.5), (8.0, 5.5, 5.0), (9.5, 7.0, 4.2)]):
        boulder("rock_big_%d" % i, 200 + i, sz, 6, 5000)
    for i, sz in enumerate([] if ONLY_CLIFFS else [(0.35, 0.3, 0.2), (0.6, 0.45, 0.3), (0.8, 0.5, 0.45), (0.5, 0.5, 0.35)]):
        boulder("scree_%d" % i, 300 + i, sz, 3, 300)
    for i, (W, H, D) in enumerate([(24.0, 16.0, 9.0), (28.0, 22.0, 10.0), (20.0, 14.0, 8.0), (26.0, 30.0, 11.0)]):
        cliff("cliff_%d" % i, 400 + i, W, H, D, 14000)
    log("done in %.0f s" % (time.time() - t0))
except Exception as e:
    import traceback
    log("ERROR", e)
    log(traceback.format_exc())
LOG.close()
