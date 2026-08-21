class_name SandField
extends Node3D

const GRID_SIZE := 72
const SPACING := 0.30
const LAYERS := 3
const GRAIN_RADIUS := 0.17
const HALF_EXTENT := (GRID_SIZE - 1) * SPACING * 0.5
const MIN_HEIGHT := -1.35
const BASE_HEIGHT := 0.35
const PALETTE := [
    Color(0.86, 0.18, 0.15),
    Color(0.15, 0.38, 0.92),
    Color(0.95, 0.79, 0.14),
    Color(0.18, 0.72, 0.31),
]

var heights := PackedFloat32Array()
var colors := PackedInt32Array()
var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh
var height_shape: HeightMapShape3D
var collision_shape: CollisionShape3D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
    add_to_group("sand")
    rng.seed = 7331
    _initialize_field()
    _build_multimesh()
    _build_collision()

func _initialize_field() -> void:
    var count := GRID_SIZE * GRID_SIZE
    heights.resize(count)
    colors.resize(count)

    for z in range(GRID_SIZE):
        for x in range(GRID_SIZE):
            var i := _index(x, z)
            var wx := _world_x(x)
            var wz := _world_z(z)
            heights[i] = BASE_HEIGHT + sin(wx * 0.34) * 0.018 + cos(wz * 0.29) * 0.018 + rng.randf_range(-0.012, 0.012)
            if wx < 0.0 and wz < 0.0:
                colors[i] = 0
            elif wx >= 0.0 and wz < 0.0:
                colors[i] = 1
            elif wx < 0.0 and wz >= 0.0:
                colors[i] = 2
            else:
                colors[i] = 3

func _build_multimesh() -> void:
    multimesh_instance = MultiMeshInstance3D.new()
    multimesh_instance.name = "SandOrbs"
    add_child(multimesh_instance)

    var sphere := SphereMesh.new()
    sphere.radius = GRAIN_RADIUS
    sphere.height = GRAIN_RADIUS * 2.0
    sphere.radial_segments = 6
    sphere.rings = 4

    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.96
    sphere.material = material

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    multimesh.mesh = sphere
    multimesh.instance_count = GRID_SIZE * GRID_SIZE * LAYERS
    multimesh_instance.multimesh = multimesh

    for z in range(GRID_SIZE):
        for x in range(GRID_SIZE):
            _update_cell_visual(_index(x, z))

func _build_collision() -> void:
    var body := StaticBody3D.new()
    body.name = "SandCollision"
    add_child(body)

    collision_shape = CollisionShape3D.new()
    collision_shape.name = "HeightMap"
    collision_shape.scale = Vector3(SPACING, 1.0, SPACING)
    body.add_child(collision_shape)

    height_shape = HeightMapShape3D.new()
    height_shape.map_width = GRID_SIZE
    height_shape.map_depth = GRID_SIZE
    height_shape.map_data = heights.duplicate()
    collision_shape.shape = height_shape

func surface_height_at(world_position: Vector3) -> float:
    var gx := clamp(world_position.x / SPACING + (GRID_SIZE - 1) * 0.5, 0.0, GRID_SIZE - 1.001)
    var gz := clamp(world_position.z / SPACING + (GRID_SIZE - 1) * 0.5, 0.0, GRID_SIZE - 1.001)
    var x0 := int(floor(gx))
    var z0 := int(floor(gz))
    var x1 := min(x0 + 1, GRID_SIZE - 1)
    var z1 := min(z0 + 1, GRID_SIZE - 1)
    var tx := gx - x0
    var tz := gz - z0
    var h00 := heights[_index(x0, z0)]
    var h10 := heights[_index(x1, z0)]
    var h01 := heights[_index(x0, z1)]
    var h11 := heights[_index(x1, z1)]
    return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)

func clamp_inside(world_position: Vector3) -> Vector3:
    world_position.x = clamp(world_position.x, -HALF_EXTENT + 0.65, HALF_EXTENT - 0.65)
    world_position.z = clamp(world_position.z, -HALF_EXTENT + 0.65, HALF_EXTENT - 0.65)
    return world_position

func apply_footprint(world_position: Vector3, yaw: float, side: int) -> void:
    var foot_half_width := 0.22
    var foot_half_length := 0.34
    var depth := 0.075
    var touched: Dictionary = {}
    var ring: Array[int] = []
    var removed := 0.0
    var center_x := int(round(world_position.x / SPACING + (GRID_SIZE - 1) * 0.5))
    var center_z := int(round(world_position.z / SPACING + (GRID_SIZE - 1) * 0.5))
    var reach := 3
    var c := cos(-yaw)
    var s := sin(-yaw)

    for z in range(max(0, center_z - reach), min(GRID_SIZE, center_z + reach + 1)):
        for x in range(max(0, center_x - reach), min(GRID_SIZE, center_x + reach + 1)):
            var dx := _world_x(x) - world_position.x
            var dz := _world_z(z) - world_position.z
            var local_x := dx * c - dz * s
            var local_z := dx * s + dz * c
            var normalized := sqrt(pow(local_x / foot_half_width, 2.0) + pow(local_z / foot_half_length, 2.0))
            var i := _index(x, z)
            if normalized <= 1.0:
                var cut := depth * (1.0 - smoothstep(0.15, 1.0, normalized))
                cut = max(cut, depth * 0.18)
                var old_height := heights[i]
                heights[i] = max(MIN_HEIGHT, heights[i] - cut)
                removed += old_height - heights[i]
                touched[i] = true
            elif normalized <= 1.65:
                ring.append(i)

    if not ring.is_empty() and removed > 0.0:
        var lip_each := removed * 0.68 / float(ring.size())
        for i in ring:
            heights[i] += lip_each
            touched[i] = true

    for i in touched.keys():
        _update_cell_visual(int(i))
    _refresh_collision()

func apply_explosion(center: Vector3, radius: float = 2.6, blast_strength: float = 12.0) -> void:
    var touched: Dictionary = {}
    var impacted: Array[int] = []
    var ring: Array[int] = []
    var removed := 0.0
    var cell_radius := int(ceil(radius / SPACING)) + 2
    var center_x := int(round(center.x / SPACING + (GRID_SIZE - 1) * 0.5))
    var center_z := int(round(center.z / SPACING + (GRID_SIZE - 1) * 0.5))

    for z in range(max(0, center_z - cell_radius), min(GRID_SIZE, center_z + cell_radius + 1)):
        for x in range(max(0, center_x - cell_radius), min(GRID_SIZE, center_x + cell_radius + 1)):
            var dx := _world_x(x) - center.x
            var dz := _world_z(z) - center.z
            var distance := sqrt(dx * dx + dz * dz)
            var i := _index(x, z)
            if distance < radius:
                var falloff := 1.0 - distance / radius
                var cut := 0.82 * falloff * falloff
                var old_height := heights[i]
                heights[i] = max(MIN_HEIGHT, heights[i] - cut)
                removed += old_height - heights[i]
                impacted.append(i)
                touched[i] = true
            elif distance < radius * 1.48:
                ring.append(i)

    if not ring.is_empty() and removed > 0.0:
        var berm_each := removed * 0.50 / float(ring.size())
        for i in ring:
            heights[i] += berm_each
            touched[i] = true

    for i in touched.keys():
        _update_cell_visual(int(i))
    _refresh_collision()

    if impacted.is_empty() or removed <= 0.0:
        return

    impacted.shuffle()
    var chunk_count := min(84, impacted.size())
    var deposit_each := removed * 0.42 / float(max(1, chunk_count))
    for n in range(chunk_count):
        var i := impacted[n]
        var x := i % GRID_SIZE
        var z := int(i / GRID_SIZE)
        var start := Vector3(_world_x(x), heights[i] + 0.28, _world_z(z))
        var horizontal := Vector3(start.x - center.x, 0.0, start.z - center.z)
        if horizontal.length_squared() < 0.001:
            horizontal = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
        horizontal = horizontal.normalized()
        var direction := (horizontal * rng.randf_range(0.65, 1.0) + Vector3.UP * rng.randf_range(0.75, 1.25)).normalized()
        var chunk := SandChunk.new()
        chunk.sand = self
        chunk.deposit_amount = deposit_each
        chunk.grain_color = PALETTE[colors[i]]
        get_tree().current_scene.add_child(chunk)
        chunk.global_position = start
        chunk.apply_central_impulse(direction * rng.randf_range(blast_strength * 0.032, blast_strength * 0.060))

func deposit(world_position: Vector3, amount: float, grain_color: Color) -> void:
    if abs(world_position.x) > HALF_EXTENT or abs(world_position.z) > HALF_EXTENT:
        return

    var color_index := _nearest_palette_index(grain_color)
    var center_x := int(round(world_position.x / SPACING + (GRID_SIZE - 1) * 0.5))
    var center_z := int(round(world_position.z / SPACING + (GRID_SIZE - 1) * 0.5))
    var targets: Array[int] = []
    for z in range(max(0, center_z - 1), min(GRID_SIZE, center_z + 2)):
        for x in range(max(0, center_x - 1), min(GRID_SIZE, center_x + 2)):
            targets.append(_index(x, z))

    if targets.is_empty():
        return

    var each := amount / float(targets.size())
    for i in targets:
        heights[i] += each
        if each > 0.004 or rng.randf() < 0.45:
            colors[i] = color_index
        _update_cell_visual(i)
    _refresh_collision()

func _nearest_palette_index(color: Color) -> int:
    var best := 0
    var best_distance := INF
    for i in range(PALETTE.size()):
        var delta := Vector3(color.r - PALETTE[i].r, color.g - PALETTE[i].g, color.b - PALETTE[i].b)
        var distance := delta.length_squared()
        if distance < best_distance:
            best_distance = distance
            best = i
    return best

func _update_cell_visual(i: int) -> void:
    if multimesh == null:
        return
    var x := i % GRID_SIZE
    var z := int(i / GRID_SIZE)
    for layer in range(LAYERS):
        var instance_index := i * LAYERS + layer
        var y := heights[i] - float(layer) * GRAIN_RADIUS * 1.28
        var transform := Transform3D(Basis.IDENTITY, Vector3(_world_x(x), y, _world_z(z)))
        multimesh.set_instance_transform(instance_index, transform)
        multimesh.set_instance_color(instance_index, PALETTE[colors[i]])

func _refresh_collision() -> void:
    if height_shape != null:
        height_shape.map_data = heights.duplicate()

func _index(x: int, z: int) -> int:
    return z * GRID_SIZE + x

func _world_x(x: int) -> float:
    return (float(x) - (GRID_SIZE - 1) * 0.5) * SPACING

func _world_z(z: int) -> float:
    return (float(z) - (GRID_SIZE - 1) * 0.5) * SPACING
