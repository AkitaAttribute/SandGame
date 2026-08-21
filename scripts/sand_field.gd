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
var collision_refresh_queued := false

func _ready() -> void:
    add_to_group("sand")
    rng.seed = 7331
    _initialize_field()
    _build_multimesh()
    _build_collision()

func _initialize_field() -> void:
    var count: int = GRID_SIZE * GRID_SIZE
    heights.resize(count)
    colors.resize(count)

    for z in range(GRID_SIZE):
        for x in range(GRID_SIZE):
            var i: int = _index(x, z)
            var wx: float = _world_x(x)
            var wz: float = _world_z(z)
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
    var gx: float = clampf(world_position.x / SPACING + float(GRID_SIZE - 1) * 0.5, 0.0, float(GRID_SIZE) - 1.001)
    var gz: float = clampf(world_position.z / SPACING + float(GRID_SIZE - 1) * 0.5, 0.0, float(GRID_SIZE) - 1.001)
    var x0: int = int(floor(gx))
    var z0: int = int(floor(gz))
    var x1: int = mini(x0 + 1, GRID_SIZE - 1)
    var z1: int = mini(z0 + 1, GRID_SIZE - 1)
    var tx: float = gx - float(x0)
    var tz: float = gz - float(z0)
    var h00: float = heights[_index(x0, z0)]
    var h10: float = heights[_index(x1, z0)]
    var h01: float = heights[_index(x0, z1)]
    var h11: float = heights[_index(x1, z1)]
    return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func clamp_inside(world_position: Vector3) -> Vector3:
    world_position.x = clampf(world_position.x, -HALF_EXTENT + 0.65, HALF_EXTENT - 0.65)
    world_position.z = clampf(world_position.z, -HALF_EXTENT + 0.65, HALF_EXTENT - 0.65)
    return world_position

func apply_footprint(world_position: Vector3, yaw: float, side: int) -> void:
    var foot_half_width: float = 0.22
    var foot_half_length: float = 0.34
    var depth: float = 0.075
    var touched: Dictionary = {}
    var ring: Array[int] = []
    var removed: float = 0.0
    var center_x: int = int(round(world_position.x / SPACING + float(GRID_SIZE - 1) * 0.5))
    var center_z: int = int(round(world_position.z / SPACING + float(GRID_SIZE - 1) * 0.5))
    var reach: int = 3
    var c: float = cos(-yaw)
    var s: float = sin(-yaw)

    for z in range(maxi(0, center_z - reach), mini(GRID_SIZE, center_z + reach + 1)):
        for x in range(maxi(0, center_x - reach), mini(GRID_SIZE, center_x + reach + 1)):
            var dx: float = _world_x(x) - world_position.x
            var dz: float = _world_z(z) - world_position.z
            var local_x: float = dx * c - dz * s
            var local_z: float = dx * s + dz * c
            var normalized: float = sqrt(pow(local_x / foot_half_width, 2.0) + pow(local_z / foot_half_length, 2.0))
            var i: int = _index(x, z)
            if normalized <= 1.0:
                var cut: float = depth * (1.0 - smoothstep(0.15, 1.0, normalized))
                cut = maxf(cut, depth * 0.18)
                var old_height: float = heights[i]
                heights[i] = maxf(MIN_HEIGHT, heights[i] - cut)
                removed += old_height - heights[i]
                touched[i] = true
            elif normalized <= 1.65:
                ring.append(i)

    if not ring.is_empty() and removed > 0.0:
        var lip_each: float = removed * 0.68 / float(ring.size())
        for i in ring:
            heights[i] += lip_each
            touched[i] = true

    for i in touched.keys():
        _update_cell_visual(int(i))
    _queue_collision_refresh()

func apply_explosion(center: Vector3, radius: float = 2.6, blast_strength: float = 12.0) -> void:
    var touched: Dictionary = {}
    var impacted: Array[int] = []
    var ring: Array[int] = []
    var source_heights: Dictionary = {}
    var source_distances: Dictionary = {}
    var removed: float = 0.0
    var cell_radius: int = int(ceil(radius / SPACING)) + 2
    var center_x: int = int(round(center.x / SPACING + float(GRID_SIZE - 1) * 0.5))
    var center_z: int = int(round(center.z / SPACING + float(GRID_SIZE - 1) * 0.5))

    for z in range(maxi(0, center_z - cell_radius), mini(GRID_SIZE, center_z + cell_radius + 1)):
        for x in range(maxi(0, center_x - cell_radius), mini(GRID_SIZE, center_x + cell_radius + 1)):
            var dx: float = _world_x(x) - center.x
            var dz: float = _world_z(z) - center.z
            var distance: float = sqrt(dx * dx + dz * dz)
            var i: int = _index(x, z)
            if distance < radius:
                var falloff: float = 1.0 - distance / radius
                var cut: float = 0.92 * falloff * falloff
                var old_height: float = heights[i]
                heights[i] = maxf(MIN_HEIGHT, heights[i] - cut)
                var cell_removed: float = old_height - heights[i]
                if cell_removed > 0.0001:
                    removed += cell_removed
                    impacted.append(i)
                    source_heights[i] = old_height
                    source_distances[i] = distance
                    touched[i] = true
            elif distance < radius * 1.38:
                ring.append(i)

    # Only a small fraction is placed instantly at the rim. Most excavated material
    # becomes physical airborne aggregate grains and returns through deposit().
    if not ring.is_empty() and removed > 0.0:
        var berm_each: float = removed * 0.07 / float(ring.size())
        for i in ring:
            heights[i] += berm_each
            touched[i] = true

    for i in touched.keys():
        _update_cell_visual(int(i))
    _queue_collision_refresh()

    if impacted.is_empty() or removed <= 0.0:
        return

    var chunk_count: int = mini(300, maxi(150, impacted.size() + int(impacted.size() * 0.35)))
    var deposit_each: float = removed * 0.86 / float(maxi(1, chunk_count))
    for n in range(chunk_count):
        var i: int = impacted[rng.randi_range(0, impacted.size() - 1)]
        var x: int = i % GRID_SIZE
        var z: int = int(i / GRID_SIZE)
        var source_height: float = float(source_heights.get(i, heights[i]))
        var source_distance: float = float(source_distances.get(i, radius * 0.5))
        var distance_ratio: float = clampf(source_distance / radius, 0.0, 1.0)

        var start := Vector3(
            _world_x(x) + rng.randf_range(-SPACING * 0.22, SPACING * 0.22),
            source_height + rng.randf_range(0.22, 0.42),
            _world_z(z) + rng.randf_range(-SPACING * 0.22, SPACING * 0.22)
        )
        var horizontal := Vector3(start.x - center.x, 0.0, start.z - center.z)
        if horizontal.length_squared() < 0.001:
            horizontal = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
        horizontal = horizontal.normalized()

        var horizontal_weight: float = lerpf(0.48, 1.30, distance_ratio)
        var vertical_weight: float = lerpf(1.55, 0.62, distance_ratio)
        vertical_weight *= rng.randf_range(0.88, 1.18)
        horizontal_weight *= rng.randf_range(0.86, 1.16)
        var direction: Vector3 = (horizontal * horizontal_weight + Vector3.UP * vertical_weight).normalized()
        var speed: float = blast_strength * lerpf(0.88, 0.48, distance_ratio) * rng.randf_range(0.82, 1.16)

        var chunk := SandChunk.new()
        chunk.sand = self
        chunk.deposit_amount = deposit_each
        chunk.grain_color = PALETTE[colors[i]]
        get_tree().current_scene.add_child(chunk)
        chunk.global_position = start
        chunk.apply_central_impulse(direction * speed * chunk.mass)

func deposit(world_position: Vector3, amount: float, grain_color: Color) -> void:
    if abs(world_position.x) > HALF_EXTENT or abs(world_position.z) > HALF_EXTENT:
        return

    var color_index: int = _nearest_palette_index(grain_color)
    var center_x: int = int(round(world_position.x / SPACING + float(GRID_SIZE - 1) * 0.5))
    var center_z: int = int(round(world_position.z / SPACING + float(GRID_SIZE - 1) * 0.5))
    var targets: Array[int] = []
    for z in range(maxi(0, center_z - 1), mini(GRID_SIZE, center_z + 2)):
        for x in range(maxi(0, center_x - 1), mini(GRID_SIZE, center_x + 2)):
            targets.append(_index(x, z))

    if targets.is_empty():
        return

    var each: float = amount / float(targets.size())
    for i in targets:
        heights[i] += each
        if each > 0.004 or rng.randf() < 0.45:
            colors[i] = color_index
        _update_cell_visual(i)
    _queue_collision_refresh()

func _nearest_palette_index(color: Color) -> int:
    var best: int = 0
    var best_distance: float = INF
    for i in range(PALETTE.size()):
        var delta := Vector3(color.r - PALETTE[i].r, color.g - PALETTE[i].g, color.b - PALETTE[i].b)
        var distance: float = delta.length_squared()
        if distance < best_distance:
            best_distance = distance
            best = i
    return best

func _update_cell_visual(i: int) -> void:
    if multimesh == null:
        return
    var x: int = i % GRID_SIZE
    var z: int = int(i / GRID_SIZE)
    for layer in range(LAYERS):
        var instance_index: int = i * LAYERS + layer
        var y: float = heights[i] - float(layer) * GRAIN_RADIUS * 1.28
        var transform := Transform3D(Basis.IDENTITY, Vector3(_world_x(x), y, _world_z(z)))
        multimesh.set_instance_transform(instance_index, transform)
        multimesh.set_instance_color(instance_index, PALETTE[colors[i]])

func _queue_collision_refresh() -> void:
    if collision_refresh_queued:
        return
    collision_refresh_queued = true
    call_deferred("_flush_collision_refresh")

func _flush_collision_refresh() -> void:
    collision_refresh_queued = false
    _refresh_collision()

func _refresh_collision() -> void:
    if height_shape != null:
        height_shape.map_data = heights.duplicate()

func _index(x: int, z: int) -> int:
    return z * GRID_SIZE + x

func _world_x(x: int) -> float:
    return (float(x) - float(GRID_SIZE - 1) * 0.5) * SPACING

func _world_z(z: int) -> float:
    return (float(z) - float(GRID_SIZE - 1) * 0.5) * SPACING
