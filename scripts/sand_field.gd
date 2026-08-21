class_name SandField
extends Node3D

const GRAVITY := 6.867
const GRAIN_RADIUS := 0.070
const GRAIN_DIAMETER := GRAIN_RADIUS * 2.0
const GRAIN_MASS := 0.025
const PACKING_SPACING := GRAIN_DIAMETER * 1.005
const PARTICLES_X := 32
const PARTICLES_Z := 32
const LAYERS := 3
const PARTICLE_COUNT := PARTICLES_X * PARTICLES_Z * LAYERS
const INITIAL_HALF_EXTENT := (PARTICLES_X - 1) * PACKING_SPACING * 0.5
const WORLD_HALF_EXTENT := INITIAL_HALF_EXTENT + 1.55
const PLAYER_SURFACE_Y := GRAIN_RADIUS * 2.0 + (LAYERS - 1) * PACKING_SPACING
const CELL_SIZE := GRAIN_DIAMETER * 1.08
const AIR_DRAG := 0.055
const FLOOR_FRICTION_RATE := 5.5
const WALL_RESTITUTION := 0.16
const GRAIN_RESTITUTION := 0.045
const GRAIN_FRICTION := 0.42
const POSITION_CORRECTION := 0.92
const SUBSTEPS := 2
const SOLVER_ITERATIONS := 1
const SLEEP_SPEED := 0.095
const SLEEP_DELAY := 0.38
const PALETTE := [
    Color(0.86, 0.18, 0.15),
    Color(0.15, 0.38, 0.92),
    Color(0.95, 0.79, 0.14),
    Color(0.18, 0.72, 0.31),
]

var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var rest_positions := PackedVector3Array()
var colors := PackedInt32Array()
var active := PackedByteArray()
var contact_flags := PackedByteArray()
var dirty := PackedByteArray()
var sleep_times := PackedFloat32Array()
var active_count := 0
var buckets: Dictionary = {}
var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh

func _ready() -> void:
    add_to_group("sand")
    _initialize_particles()
    _build_multimesh()
    _update_all_visuals()

func _physics_process(delta: float) -> void:
    if active_count <= 0:
        return

    var frame_dt: float = minf(delta, 1.0 / 30.0)
    var step_dt: float = frame_dt / float(SUBSTEPS)

    for _substep in range(SUBSTEPS):
        if active_count <= 0:
            break
        _reset_contact_flags()
        _integrate_active(step_dt)
        _constrain_active(step_dt, true)
        for solver_iteration in range(SOLVER_ITERATIONS):
            _build_spatial_hash()
            _solve_active_contacts()
            _constrain_active(step_dt, solver_iteration == 0)
        _update_sleep(step_dt)

    _update_dirty_visuals()

func _initialize_particles() -> void:
    positions.resize(PARTICLE_COUNT)
    velocities.resize(PARTICLE_COUNT)
    rest_positions.resize(PARTICLE_COUNT)
    colors.resize(PARTICLE_COUNT)
    active.resize(PARTICLE_COUNT)
    contact_flags.resize(PARTICLE_COUNT)
    dirty.resize(PARTICLE_COUNT)
    sleep_times.resize(PARTICLE_COUNT)

    var index: int = 0
    for layer in range(LAYERS):
        for z in range(PARTICLES_Z):
            for x in range(PARTICLES_X):
                var px: float = (float(x) - float(PARTICLES_X - 1) * 0.5) * PACKING_SPACING
                var pz: float = (float(z) - float(PARTICLES_Z - 1) * 0.5) * PACKING_SPACING
                var py: float = GRAIN_RADIUS + float(layer) * PACKING_SPACING
                var p := Vector3(px, py, pz)
                positions[index] = p
                rest_positions[index] = p
                velocities[index] = Vector3.ZERO
                colors[index] = _initial_color_index(p)
                active[index] = 0
                contact_flags[index] = 0
                dirty[index] = 1
                sleep_times[index] = 0.0
                index += 1

func _initial_color_index(position: Vector3) -> int:
    if position.x < 0.0 and position.z < 0.0:
        return 0
    if position.x >= 0.0 and position.z < 0.0:
        return 1
    if position.x < 0.0 and position.z >= 0.0:
        return 2
    return 3

func _build_multimesh() -> void:
    multimesh_instance = MultiMeshInstance3D.new()
    multimesh_instance.name = "SimulatedSandGrains"
    add_child(multimesh_instance)

    var sphere := SphereMesh.new()
    sphere.radius = GRAIN_RADIUS
    sphere.height = GRAIN_DIAMETER
    sphere.radial_segments = 6
    sphere.rings = 4

    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.97
    sphere.material = material

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    multimesh.mesh = sphere
    multimesh.instance_count = PARTICLE_COUNT
    multimesh_instance.multimesh = multimesh

    for i in range(PARTICLE_COUNT):
        multimesh.set_instance_color(i, PALETTE[colors[i]])

func _wake(index: int) -> void:
    if active[index] != 0:
        sleep_times[index] = 0.0
        return
    active[index] = 1
    active_count += 1
    sleep_times[index] = 0.0

func _sleep(index: int) -> void:
    if active[index] == 0:
        return
    active[index] = 0
    active_count = maxi(0, active_count - 1)
    velocities[index] = Vector3.ZERO
    sleep_times[index] = 0.0
    dirty[index] = 1

func _reset_contact_flags() -> void:
    for i in range(PARTICLE_COUNT):
        if active[i] != 0:
            contact_flags[i] = 0

func _integrate_active(dt: float) -> void:
    var drag: float = 1.0 / (1.0 + AIR_DRAG * dt)
    for i in range(PARTICLE_COUNT):
        if active[i] == 0:
            continue
        var velocity: Vector3 = velocities[i]
        var position: Vector3 = positions[i]
        velocity.y -= GRAVITY * dt
        velocity *= drag
        position += velocity * dt
        positions[i] = position
        velocities[i] = velocity
        dirty[i] = 1

func _constrain_active(dt: float, apply_floor_friction: bool) -> void:
    var floor_drag: float = maxf(0.0, 1.0 - FLOOR_FRICTION_RATE * dt)
    var limit: float = WORLD_HALF_EXTENT - GRAIN_RADIUS

    for i in range(PARTICLE_COUNT):
        if active[i] == 0:
            continue

        var position: Vector3 = positions[i]
        var velocity: Vector3 = velocities[i]

        if _vector_is_invalid(position) or _vector_is_invalid(velocity):
            positions[i] = rest_positions[i]
            velocities[i] = Vector3.ZERO
            dirty[i] = 1
            _sleep(i)
            continue

        if position.y < GRAIN_RADIUS:
            position.y = GRAIN_RADIUS
            contact_flags[i] = 1
            if velocity.y < 0.0:
                velocity.y = -velocity.y * GRAIN_RESTITUTION
            if apply_floor_friction:
                velocity.x *= floor_drag
                velocity.z *= floor_drag
                if absf(velocity.y) < 0.018:
                    velocity.y = 0.0
                if Vector2(velocity.x, velocity.z).length_squared() < 0.00005:
                    velocity.x = 0.0
                    velocity.z = 0.0

        if position.x < -limit:
            position.x = -limit
            contact_flags[i] = 1
            if velocity.x < 0.0:
                velocity.x = -velocity.x * WALL_RESTITUTION
        elif position.x > limit:
            position.x = limit
            contact_flags[i] = 1
            if velocity.x > 0.0:
                velocity.x = -velocity.x * WALL_RESTITUTION

        if position.z < -limit:
            position.z = -limit
            contact_flags[i] = 1
            if velocity.z < 0.0:
                velocity.z = -velocity.z * WALL_RESTITUTION
        elif position.z > limit:
            position.z = limit
            contact_flags[i] = 1
            if velocity.z > 0.0:
                velocity.z = -velocity.z * WALL_RESTITUTION

        positions[i] = position
        velocities[i] = velocity
        dirty[i] = 1

func _vector_is_invalid(value: Vector3) -> bool:
    return is_nan(value.x) or is_nan(value.y) or is_nan(value.z) or is_inf(value.x) or is_inf(value.y) or is_inf(value.z)

func _build_spatial_hash() -> void:
    buckets.clear()
    for i in range(PARTICLE_COUNT):
        var cell: Vector3i = _cell_for_position(positions[i])
        if not buckets.has(cell):
            buckets[cell] = []
        var bucket: Array = buckets[cell]
        bucket.append(i)

func _cell_for_position(position: Vector3) -> Vector3i:
    return Vector3i(
        int(floor(position.x / CELL_SIZE)),
        int(floor(position.y / CELL_SIZE)),
        int(floor(position.z / CELL_SIZE))
    )

func _solve_active_contacts() -> void:
    for i in range(PARTICLE_COUNT):
        if active[i] == 0:
            continue

        var cell: Vector3i = _cell_for_position(positions[i])
        for oy in range(-1, 2):
            for oz in range(-1, 2):
                for ox in range(-1, 2):
                    var neighbor_cell := Vector3i(cell.x + ox, cell.y + oy, cell.z + oz)
                    if not buckets.has(neighbor_cell):
                        continue
                    var bucket: Array = buckets[neighbor_cell]
                    for value in bucket:
                        var j: int = int(value)
                        if j == i:
                            continue
                        if active[j] != 0 and j < i:
                            continue
                        _resolve_grain_pair(i, j)

func _resolve_grain_pair(i: int, j: int) -> void:
    var a: Vector3 = positions[i]
    var b: Vector3 = positions[j]
    var delta: Vector3 = b - a
    var distance_squared: float = delta.length_squared()
    var minimum_distance_squared: float = GRAIN_DIAMETER * GRAIN_DIAMETER
    if distance_squared >= minimum_distance_squared:
        return

    var normal: Vector3
    var distance: float
    if distance_squared < 0.00000001:
        normal = Vector3.RIGHT if ((i + j) % 2) == 0 else Vector3.FORWARD
        distance = 0.0001
    else:
        distance = sqrt(distance_squared)
        normal = delta / distance

    _wake(j)
    contact_flags[i] = 1
    contact_flags[j] = 1

    var penetration: float = GRAIN_DIAMETER - distance
    var correction: Vector3 = normal * penetration * 0.5 * POSITION_CORRECTION
    a -= correction
    b += correction

    var velocity_a: Vector3 = velocities[i]
    var velocity_b: Vector3 = velocities[j]
    var relative_velocity: Vector3 = velocity_b - velocity_a
    var normal_speed: float = relative_velocity.dot(normal)

    if normal_speed < 0.0:
        var normal_impulse_speed: float = -(1.0 + GRAIN_RESTITUTION) * normal_speed * 0.5
        velocity_a -= normal * normal_impulse_speed
        velocity_b += normal * normal_impulse_speed

        var tangent: Vector3 = relative_velocity - normal * normal_speed
        var tangent_length: float = tangent.length()
        if tangent_length > 0.0001:
            var tangent_direction: Vector3 = tangent / tangent_length
            var friction_speed: float = minf(tangent_length * 0.5, normal_impulse_speed * GRAIN_FRICTION)
            velocity_a += tangent_direction * friction_speed
            velocity_b -= tangent_direction * friction_speed

    positions[i] = a
    positions[j] = b
    velocities[i] = velocity_a
    velocities[j] = velocity_b
    dirty[i] = 1
    dirty[j] = 1

func _update_sleep(dt: float) -> void:
    var sleep_speed_squared: float = SLEEP_SPEED * SLEEP_SPEED
    for i in range(PARTICLE_COUNT):
        if active[i] == 0:
            continue

        if contact_flags[i] != 0 and velocities[i].length_squared() <= sleep_speed_squared:
            sleep_times[i] += dt
            if sleep_times[i] >= SLEEP_DELAY:
                _sleep(i)
        else:
            sleep_times[i] = 0.0

func apply_radial_impulse(center: Vector3, radius: float = 1.65, impulse_speed: float = 8.5) -> void:
    var radius_squared: float = radius * radius
    for i in range(PARTICLE_COUNT):
        var offset: Vector3 = positions[i] - center
        var distance_squared: float = offset.length_squared()
        if distance_squared >= radius_squared:
            continue

        var distance: float = sqrt(maxf(distance_squared, 0.000001))
        var direction: Vector3 = offset / distance
        var falloff: float = pow(1.0 - distance / radius, 1.25)
        var delta_velocity: float = impulse_speed * (0.16 + 0.84 * falloff)
        _wake(i)
        velocities[i] += direction * delta_velocity
        dirty[i] = 1

func interact_sphere(center: Vector3, radius: float, body_velocity: Vector3, _body_mass: float, _dt: float) -> Vector3:
    var reaction_impulse := Vector3.ZERO
    var minimum_distance: float = radius + GRAIN_RADIUS
    var minimum_distance_squared: float = minimum_distance * minimum_distance

    for i in range(PARTICLE_COUNT):
        var offset: Vector3 = positions[i] - center
        var distance_squared: float = offset.length_squared()
        if distance_squared >= minimum_distance_squared:
            continue

        var normal: Vector3
        var distance: float
        if distance_squared < 0.00000001:
            normal = Vector3.UP
            distance = 0.0001
        else:
            distance = sqrt(distance_squared)
            normal = offset / distance

        _wake(i)
        contact_flags[i] = 1

        var penetration: float = minimum_distance - distance
        var position: Vector3 = positions[i] + normal * penetration * 0.92
        var grain_velocity: Vector3 = velocities[i]
        var closing_speed: float = (body_velocity - grain_velocity).dot(normal)

        if closing_speed > 0.0:
            var transfer_delta_velocity: Vector3 = normal * closing_speed * 0.72
            grain_velocity += transfer_delta_velocity
            reaction_impulse -= transfer_delta_velocity * GRAIN_MASS

        positions[i] = position
        velocities[i] = grain_velocity
        dirty[i] = 1

    return reaction_impulse

func surface_height_at(_world_position: Vector3) -> float:
    return PLAYER_SURFACE_Y

func clamp_inside(world_position: Vector3) -> Vector3:
    var player_limit: float = WORLD_HALF_EXTENT - 0.65
    world_position.x = clampf(world_position.x, -player_limit, player_limit)
    world_position.z = clampf(world_position.z, -player_limit, player_limit)
    return world_position

func grain_count() -> int:
    return PARTICLE_COUNT

func active_grain_count() -> int:
    return active_count

func _update_all_visuals() -> void:
    if multimesh == null:
        return
    for i in range(PARTICLE_COUNT):
        multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
        dirty[i] = 0

func _update_dirty_visuals() -> void:
    if multimesh == null:
        return
    for i in range(PARTICLE_COUNT):
        if dirty[i] == 0:
            continue
        multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
        dirty[i] = 0
