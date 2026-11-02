# Repartidor GOGO en moto — modelo 3D estilo juguete, construido con primitivas.
# Uso: blender --background --factory-startup --python gogo_rider.py -- <carpeta_salida>
import bpy, bmesh, math, os, sys
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.expanduser("~/Downloads/gogo_rider")
os.makedirs(OUT, exist_ok=True)

# ── Escena limpia ──────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ── Materiales ─────────────────────────────────────────────────────────────
def mat(name, color, rough=0.35, metal=0.0, coat=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    for key in ("Coat Weight", "Clearcoat"):
        if key in b.inputs:
            b.inputs[key].default_value = coat
            break
    if emit:
        for key in ("Emission Color", "Emission"):
            if key in b.inputs:
                b.inputs[key].default_value = (*emit, 1)
                break
        if "Emission Strength" in b.inputs:
            b.inputs["Emission Strength"].default_value = 2.0
    return m

ORANGE = mat("Naranja_GOGO", (0.90, 0.13, 0.005), rough=0.32, coat=0.25)
BLACK  = mat("Negro", (0.015, 0.015, 0.017), rough=0.45)
VISOR  = mat("Visor", (0.01, 0.01, 0.012), rough=0.08, coat=1.0)
PANTS  = mat("Pantalon", (0.022, 0.022, 0.025), rough=0.7)
WHITE  = mat("Blanco", (0.92, 0.92, 0.92), rough=0.5)
METAL  = mat("Metal", (0.75, 0.76, 0.78), rough=0.25, metal=1.0)
TIRE   = mat("Llanta", (0.02, 0.02, 0.02), rough=0.85)
LIGHT  = mat("Faro", (1.0, 0.97, 0.85), rough=0.1, emit=(1.0, 0.95, 0.8))
RED    = mat("Calavera", (0.7, 0.03, 0.02), rough=0.2, emit=(0.6, 0.02, 0.01))
AMBER  = mat("Direccional", (1.0, 0.55, 0.05), rough=0.2, emit=(1.0, 0.5, 0.05))

ROOT = bpy.data.objects.new("GOGO_Repartidor", None)
scene.collection.objects.link(ROOT)

def finish(obj, material, smooth=True, bevel=0.0, subsurf=0):
    obj.data.materials.append(material)
    if smooth and obj.type == "MESH":
        obj.data.polygons.foreach_set("use_smooth", [True] * len(obj.data.polygons))
    if bevel:
        m = obj.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 3
        m.limit_method = "ANGLE"
    if subsurf:
        m = obj.modifiers.new("Subsurf", "SUBSURF")
        m.levels = subsurf
        m.render_levels = subsurf
    obj.parent = ROOT
    return obj

def sphere(name, loc, scale, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=14, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    return finish(o, material)

def box(name, loc, size, material, bevel=0.03, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, material, bevel=bevel)

def cyl(name, loc, radius, depth, material, rot=(0, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return finish(o, material, bevel=min(radius, depth) * 0.25)

def limb(name, a, b, radius, material):
    """Cilindro con puntas redondas entre dos puntos (brazos, piernas)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=d.length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    finish(o, material)
    for p in (a, b):
        sphere(name + "_art", p, (radius, radius, radius), material)
    return o

def torus(name, loc, major, minor, material):
    bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=12, major_radius=major,
                                     minor_radius=minor, location=loc, rotation=(math.pi / 2, 0, 0))
    o = bpy.context.active_object
    o.name = name
    return finish(o, material)

RX = (math.pi / 2, 0, 0)  # eje Y (cilindros "de lado")
RY = (0, math.pi / 2, 0)  # eje X

# ── Moto (mira hacia +X) ───────────────────────────────────────────────────
for side, x in (("Trasera", -0.62), ("Delantera", 0.78)):
    torus(f"Llanta_{side}", (x, 0, 0.24), 0.17, 0.075, TIRE)
    cyl(f"Rin_{side}", (x, 0, 0.24), 0.13, 0.11, METAL, rot=RX)
    cyl(f"Eje_{side}", (x, 0, 0.24), 0.04, 0.16, METAL, rot=RX)

sphere("Carroceria_Trasera", (-0.38, 0, 0.50), (0.56, 0.30, 0.27), ORANGE)
sphere("Tapa_Lateral", (-0.42, -0.21, 0.52), (0.30, 0.06, 0.07), ORANGE)
box("Piso", (0.17, 0, 0.30), (0.62, 0.36, 0.07), ORANGE, bevel=0.03)
box("Escudo", (0.55, 0, 0.62), (0.16, 0.42, 0.62), ORANGE, bevel=0.07, rot=(0, math.radians(-14), 0))
sphere("Salpicadera", (0.80, 0, 0.42), (0.30, 0.17, 0.11), ORANGE)
cyl("Horquilla", (0.74, 0, 0.36), 0.03, 0.34, METAL, rot=(0, math.radians(-14), 0))
cyl("Columna", (0.64, 0, 0.98), 0.07, 0.30, ORANGE, rot=(0, math.radians(-14), 0))
sphere("Cabeza_Manubrio", (0.68, 0, 1.12), (0.13, 0.15, 0.09), ORANGE)
cyl("Manubrio", (0.62, 0, 1.15), 0.022, 0.62, BLACK, rot=RX)
for s in (-1, 1):
    cyl(f"Puno_{s}", (0.62, s * 0.30, 1.15), 0.03, 0.10, BLACK, rot=RX)
    limb(f"Espejo_Brazo_{s}", (0.62, s * 0.20, 1.17), (0.58, s * 0.24, 1.38), 0.012, BLACK)
    sphere(f"Espejo_{s}", (0.58, s * 0.24, 1.42), (0.06, 0.02, 0.06), ORANGE)
cyl("Faro_Aro", (0.79, 0, 1.12), 0.09, 0.06, METAL, rot=RY)
cyl("Faro", (0.82, 0, 1.12), 0.075, 0.02, LIGHT, rot=RY)
sphere("Direccional", (0.66, -0.19, 0.78), (0.05, 0.015, 0.03), AMBER)
box("Asiento", (-0.30, 0, 0.80), (0.62, 0.32, 0.10), BLACK, bevel=0.05)
cyl("Escape", (-0.55, -0.20, 0.30), 0.06, 0.40, METAL, rot=RY)
sphere("Calavera", (-0.93, 0, 0.58), (0.03, 0.10, 0.05), RED)
box("Parrilla", (-0.72, 0, 0.86), (0.48, 0.42, 0.04), BLACK, bevel=0.01)

# ── Caja de entregas con logo ──────────────────────────────────────────────
box("Caja", (-0.72, 0, 1.13), (0.52, 0.50, 0.46), ORANGE, bevel=0.05)
box("Caja_Tapa", (-0.72, 0, 1.37), (0.54, 0.52, 0.05), BLACK, bevel=0.015)
box("Caja_Base", (-0.72, 0, 0.90), (0.54, 0.52, 0.04), BLACK, bevel=0.015)

font = None
for f in ("C:/Windows/Fonts/ariblk.ttf", "C:/Windows/Fonts/arialbd.ttf"):
    if os.path.exists(f):
        font = bpy.data.fonts.load(f)
        break

def logo(text, size, loc, rot):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    t = bpy.context.active_object
    t.data.body = text
    if font:
        t.data.font = font
    t.data.size = size
    t.data.extrude = 0.006
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.space_line = 0.85
    t.data.resolution_u = 4
    t.data.materials.append(WHITE)
    bpy.ops.object.convert(target="MESH")
    t.parent = ROOT
    return t

for side, y, rz in (("Izq", -0.258, 0), ("Der", 0.258, math.pi)):
    logo("GO\nGO", 0.19, (-0.72, y, 1.19), (math.pi / 2, 0, rz)).name = f"Logo_GOGO_{side}"
    logo("FOOD", 0.07, (-0.72, y, 0.985), (math.pi / 2, 0, rz)).name = f"Logo_FOOD_{side}"

# ── Repartidor ─────────────────────────────────────────────────────────────
for s in (-1, 1):
    y = s * 0.11
    limb(f"Muslo_{s}", (-0.22, y, 0.93), (0.12, y * 1.15, 0.92), 0.085, PANTS)
    limb(f"Espinilla_{s}", (0.12, y * 1.15, 0.92), (0.20, y * 1.15, 0.45), 0.075, PANTS)
    box(f"Tenis_{s}", (0.27, y * 1.15, 0.38), (0.24, 0.12, 0.10), WHITE, bevel=0.04)
    box(f"Suela_{s}", (0.27, y * 1.15, 0.335), (0.25, 0.125, 0.025), BLACK, bevel=0.01)

sphere("Torso", (-0.14, 0, 1.22), (0.21, 0.23, 0.32), ORANGE, rot=(0, math.radians(12), 0))
box("Cierre", (0.04, 0, 1.24), (0.02, 0.02, 0.40), BLACK, bevel=0.005, rot=(0, math.radians(12), 0))
sphere("Cadera", (-0.20, 0, 0.95), (0.19, 0.20, 0.12), PANTS)
for s in (-1, 1):
    limb(f"Brazo_{s}", (-0.06, s * 0.21, 1.40), (0.24, s * 0.25, 1.22), 0.07, ORANGE)
    limb(f"Antebrazo_{s}", (0.24, s * 0.25, 1.22), (0.55, s * 0.28, 1.16), 0.062, ORANGE)
    sphere(f"Guante_{s}", (0.59, s * 0.28, 1.16), (0.07, 0.065, 0.065), BLACK)
cyl("Cuello", (-0.04, 0, 1.52), 0.07, 0.10, BLACK)
sphere("Casco", (-0.02, 0, 1.74), (0.25, 0.24, 0.25), ORANGE)
sphere("Visor", (0.085, 0, 1.68), (0.20, 0.222, 0.19), VISOR)
for s in (-1, 1):
    cyl(f"Boton_Casco_{s}", (0.04, s * 0.235, 1.70), 0.035, 0.03, BLACK, rot=RX)

# ── Exportar GLB ───────────────────────────────────────────────────────────
glb = os.path.join(OUT, "gogo_rider.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_apply=True)

# ── Cámara, luces y render de vista previa ─────────────────────────────────
def add_light(kind, loc, energy, size=None, rot=(0, 0, 0)):
    data = bpy.data.lights.new(kind, kind)
    data.energy = energy
    if size and hasattr(data, "size"):
        data.size = size
    o = bpy.data.objects.new(kind, data)
    o.location = loc
    o.rotation_euler = rot
    scene.collection.objects.link(o)
    return o

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

key = add_light("AREA", (1.5, -2.5, 3.0), 320, size=2.5)
look_at(key, (0, 0, 0.9))
fill = add_light("AREA", (-2.5, -1.5, 1.5), 110, size=3)
look_at(fill, (0, 0, 0.9))
rim = add_light("AREA", (-0.5, 2.5, 2.5), 180, size=2)
look_at(rim, (0, 0, 1.0))

world = bpy.data.worlds.new("Fondo")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.95, 0.95, 0.95, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.35
scene.world = world

cam_data = bpy.data.cameras.new("Camara")
cam_data.lens = 70
cam = bpy.data.objects.new("Camara", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 48
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

views = {
    "lado": (0.0, -6.2, 1.35),
    "tres_cuartos": (4.0, -4.6, 2.1),
    "atras": (-4.4, -3.6, 1.9),
}
for name, pos in views.items():
    cam.location = pos
    look_at(cam, (0.0, 0, 0.88))
    scene.render.filepath = os.path.join(OUT, f"vista_{name}.png")
    bpy.ops.render.render(write_still=True)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "gogo_rider.blend"))
print("LISTO:", OUT)
