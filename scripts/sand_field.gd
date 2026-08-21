class_name SandField
extends Node3D

const GRAVITY := 6.867
const GRAIN_RADIUS := 0.170
const GRAIN_DIAMETER := GRAIN_RADIUS * 2.0
const GRAIN_MASS := 0.05
const PACKING_SPACING := GRAIN_DIAMETER * 1.005
const PARTICLES_X := 32
const PARTICLES_Z := 32
const LAYERS := 3
const PARTICLE_COUNT := PARTICLES_X * PARTICLES_Z * LAYERS

const BED_HALF_EXTENT := (PARTICLES_X - 1) * PACKING_SPACING * 0.5
const BOUNDARY_HALF_EXTENT := BED_HALF_EXTENT + GRAIN_RADIUS
const PLAYER_SURFACE_Y := GRAIN_RADIUS * 2.0 + (LAYERS - 1) * PACKING_SPACING

const CELL_SIZE := GRAIN_DIAMETER * 1.08
const GRID_Y_CELLS := 32

const AIR_DRAG := 0.045
const FLOOR_FRICTION_RATE := 5.2
const WALL_RESTITUTION := 0.10
const GRAIN_RESTITUTION := 0.035
const GRAIN_FRICTION := 0.48
const POSITION_CORRECTION := 0.90

const SIM_HZ := 30.0
const SIM_DT := 1.0 / SIM_HZ
const MAX_SIM_STEPS_PER_FRAME := 2
const HIGH_SPEED_SUBSTEP_THRESHOLD := 4.5

const SLEEP_SPEED := 0.11
const SLEEP_DELAY := 0.42

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

var active_flags := PackedByteArray()
var active_slots := PackedInt32Array()
var sleep_times := PackedFloat32Array()
var contact_flags := PackedByteArray()
var active_indices: Array[int] = []

var dirty_flags := PackedByteArray()
var dirty_indices: Array[int] = []

# Persistent broadphase. Every grain lives in exactly one fixed grid cell.
# Only grains that cross a cell boundary update these links.
var cell_heads := PackedInt32Array()
var next_in_cell := PackedInt32Array()
var prev_in_cell := PackedInt32Array()
var particle_cell := PackedInt32Array()
var grid_x := 0
var grid_z := 0
var grid_cell_count := 0

var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh
var simulation_accumulator := 0.0

func _ready() -> void:
    add_to_group("sand")
    _initialize_grid()
    _initialize_particles()
    _build_multimesh()
    _update_all_visuals()

func _physics_process(delta: float) -> void:
    if active_indices.is_empty():
        simulation_accumulator = 0.0
        _update_dirty_visuals()
        return

    simulation_accumulator += minf(delta, 0.10)
    var steps := 0

    while simulation_accumulator >= SIM_DT and steps < MAX_SIM_STEPS_PER_FRAME:
        _simulate_step(SIM_DT)
        simulation_accumulator -= SIM_DT
        steps += 1

    # Do not allow a long hitch to create a physics catch-up spiral.
    if steps >= MAX_SIM_STEPS_PER_FRAME and simulation_accumulator > SIM_DT:
        simulation_accumulator = SIM_DT

    _update_dirty_visuals()

func _simulate_step(dt: float) -> void:
    if active_indices.is_empty():
        return

    var substeps := 1
    if _max_active_speed_squared() > HIGH_SPEED_SUBSTEP_THRESHOLD * HIGH_SPEED_SUBSTEP_THRESHOLD:
        substeps = 2

    var step_dt := dt / float(substeps)
    for _substep in range(substeps):
        if active_indices.is_empty():
            break
        _reset_active_contact_flags()
        _integrate_active(step_dt)
        _constrain_active(step_dt, true)
        _solve_active_contacts()
        _constrain_active(step_dt, false)
        _update_sleep(step_dt)

func _initialize_grid() -> void:
    grid_x = int(ceil((BOUNDARY_HALF_EXTENT * 2.0) / CELL_SIZE)) + 2
    grid_z = grid_x
    grid_cell_count = grid_x * GRID_Y_CELLS * grid_z

    cell_heads.resize(grid_cell_count)
    cell_heads.fill(-1)

    next_in_cell.resize(PARTICLE_COUNT)
    next_in_cell.fill(-1)

    prev_in_cell.resize(PARTICLE_COUNT)
    prev_in_cell.fill(-1)

    particle_cell.resize(PARTICLE_COUNT)
    particle_cell.fill(-1)

func _initialize_particles() -> void:
    positions.resize(PARTICLE_COUNT)
    velocities.resize(PARTICLE_COUNT)
    rest_positions.resize(PARTICLE_COUNT)
    colors.resize(PARTICLE_COUNT)

    active_flags.resize(PARTICLE_COUNT)
    active_slots.resize(PARTICLE_COUNT)
    active_slots.fill(-1)
    sleep_times.resize(PARTICLE_COUNT)
    contact_flags.resize(PARTICLE_COUNT)

    dirty_flags.resize(PARTICLE_COUNT)

    var index := 0
    for layer in range(LAYERS):
        for z in range(PARTICLES_Z):
            for x in range(PARTICLES_X):
                var px := (float(x) - float(PARTICLES_X - 1) * 0.5) * PACKING_SPACING
                var pz := (float(z) - float(PARTICLES_Z - 1) * 0.5) * PACKING_SPACING
                var py := GRAIN_RADIUS + float(layer) * PACKING_SPACING
                var p := Vector3(px, py, pz)

                positions[index] = p
                rest_positions[index] = p
                velocities[index] = Vector3.ZERO
                colors[index] = _initial_color_index(p)

                active_flags[index] = 0
                sleep_times[index] = 0.0
                contact_flags[index] = 0
                dirty_flags[index] = 1
                dirty_indices.append(index)

                _insert_particle_into_cell(index, _cell_for_position(p))
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
    if active_flags[index] != 0:
        sleep_times[index] = 0.0
        return

    active_flags[index] = 1
    active_slots[index] = active_indices.size()
    active_indices.append(index)
    sleep_times[index] = 0.0

func _sleep(index: int) -> void:
    if active_flags[index] == 0:
        return

    var slot := active_slots[index]
    var last_slot := active_indices.size() - 1
    var last_index := active_indices[last_slot]

    if slot != last_slot:
        active_indices[slot] = last_index
        active_slots[last_index] = slot

    active_indices.pop_back()
    active_flags[index] = 0
    active_slots[index] = -1
    velocities[index] = Vector3.ZERO
    sleep_times[index] = 0.0
    _mark_dirty(index)

func _mark_dirty(index: int) -> void:
    if dirty_flags[index] != 0:
        return
    dirty_flags[index] = 1
    dirty_indices.append(index)

func _reset_active_contact_flags() -> void:
    for index in active_indices:
        contact_flags[index] = 0

func _max_active_speed_squared() -> float:
    var maximum := 0.0
    for index in active_indices:
        maximum = maxf(maximum, velocities[index].length_squared())
    return maximum

func _integrate_active(dt: float) -> void:
    var drag := 1.0 / (1.0 + AIR_DRAG * dt)

    for index in active_indices:
        var velocity := velocities[index]
        var position := positions[index]

        velocity.y -= GRAVITY * dt
        velocity *= drag
        position += velocity * dt

        positions[index] = position
        velocities[index] = velocity
        _move_particle_cell_if_needed(index)
        _mark_dirty(index)

func _constrain_active(dt: float, apply_floor_friction: bool) -> void:
    var floor_drag := maxf(0.0, 1.0 - FLOOR_FRICTION_RATE * dt)
    var limit := BOUNDARY_HALF_EXTENT - GRAIN_RADIUS

    for index in active_indices:
        var position := positions[index]
        var velocity := velocities[index]

        if _vector_is_invalid(position) or _vector_is_invalid(velocity):
            _restore_particle(index)
            continue

        if position.y < GRAIN_RADIUS:
            position.y = GRAIN_RADIUS
            contact_flags[index] = 1
            if velocity.y < 0.0:
                velocity.y = -velocity.y * GRAIN_RESTITUTION

            if apply_floor_friction:
                velocity.x *= floor_drag
                velocity.z *= floor_drag
                if absf(velocity.y) < 0.020:
                    velocity.y = 0.0
                if Vector2(velocity.x, velocity.z).length_squared() < 0.00008:
                    velocity.x = 0.0
                    velocity.z = 0.0

        if position.x < -limit:
            position.x = -limit
            contact_flags[index] = 1
            if velocity.x < 0.0:
                velocity.x = -velocity.x * WALL_RESTITUTION
        elif position.x > limit:
            position.x = limit
            contact_flags[index] = 1
            if velocity.x > 0.0:
                velocity.x = -velocity.x * WALL_RESTITUTION

        if position.z < -limit:
            position.z = -limit
            contact_flags[index] = 1
            if velocity.z < 0.0:
                velocity.z = -velocity.z * WALL_RESTITUTION
        elif position.z > limit:
            position.z = limit
            contact_flags[index] = 1
            if velocity.z > 0.0:
                velocity.z = -velocity.z * WALL_RESTITUTION

        positions[index] = position
        velocities[index] = velocity
        _move_particle_cell_if_needed(index)
        _mark_dirty(index)

func _restore_particle(index: int) -> void:
    _remove_particle_from_cell(index)
    positions[index] = rest_positions[index]
    velocities[index] = Vector3.ZERO
    _insert_particle_into_cell(index, _cell_for_position(positions[index]))
    contact_flags[index] = 1
    sleep_times[index] = SLEEP_DELAY
    _mark_dirty(index)

func _vector_is_invalid(value: Vector3) -> bool:
    return (
        is_nan(value.x) or is_nan(value.y) or is_nan(value.z)
        or is_inf(value.x) or is_inf(value.y) or is_inf(value.z)
    )

func _solve_active_contacts() -> void:
    # Newly woken grains are appended to active_indices but wait until the next
    # substep. This prevents a single contact chain from recursively exploding
    # the amount of work in the current solver pass.
    var active_at_start := active_indices.size()

    for slot in range(active_at_start):
        var i := active_indices[slot]
        var cell := particle_cell[i]
        var cx := cell % grid_x
        var remainder := int(cell / grid_x)
        var cz := remainder % grid_z
        var cy := int(remainder / grid_z)

        for oy in range(-1, 2):
            var ny := cy + oy
            if ny < 0 or ny >= GRID_Y_CELLS:
                continue

            for oz in range(-1, 2):
                var nz := cz + oz
                if nz < 0 or nz >= grid_z:
                    continue

                for ox in range(-1, 2):
                    var nx := cx + ox
                    if nx < 0 or nx >= grid_x:
                        continue

                    var neighbor_cell := _flat_cell(nx, ny, nz)
                    var j := cell_heads[neighbor_cell]

                    while j >= 0:
                        var next_j := next_in_cell[j]

                        if j != i:
                            # Active/active pairs are solved once. Sleeping
                            # neighbors are still considered because they may
                            # need to wake when struck.
                            if active_flags[j] == 0 or j > i:
                                _resolve_grain_pair(i, j)

                        j = next_j

func _resolve_grain_pair(i: int, j: int) -> void:
    var a := positions[i]
    var b := positions[j]
    var delta := b - a
    var distance_squared := delta.length_squared()
    var minimum_distance_squared := GRAIN_DIAMETER * GRAIN_DIAMETER

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

    var penetration := GRAIN_DIAMETER - distance
    var velocity_a := velocities[i]
    var velocity_b := velocities[j]
    var relative_velocity := velocity_b - velocity_a
    var normal_speed := relative_velocity.dot(normal)

    # A sleeping grain is effectively part of the packed bed until a moving
    # neighbor actually reaches it. Once contact occurs it joins the active
    # island, but it will not be integrated until the next substep.
    if active_flags[j] == 0:
        if penetration > 0.0015 or normal_speed < -0.035:
            _wake(j)
        else:
            return

    contact_flags[i] = 1
    contact_flags[j] = 1

    var correction := normal * penetration * 0.5 * POSITION_CORRECTION
    a -= correction
    b += correction

    if normal_speed < 0.0:
        var normal_impulse_speed := -(1.0 + GRAIN_RESTITUTION) * normal_speed * 0.5
        velocity_a -= normal * normal_impulse_speed
        velocity_b += normal * normal_impulse_speed

        var tangent := relative_velocity - normal * normal_speed
        var tangent_length := tangent.length()

        if tangent_length > 0.0001:
            var tangent_direction := tangent / tangent_length
            var friction_speed := minf(
                tangent_length * 0.5,
                normal_impulse_speed * GRAIN_FRICTION
            )
            velocity_a += tangent_direction * friction_speed
            velocity_b -= tangent_direction * friction_speed

    positions[i] = a
    positions[j] = b
    velocities[i] = velocity_a
    velocities[j] = velocity_b

    _move_particle_cell_if_needed(i)
    _move_particle_cell_if_needed(j)
    _mark_dirty(i)
    _mark_dirty(j)

func _update_sleep(dt: float) -> void:
    var sleep_speed_squared := SLEEP_SPEED * SLEEP_SPEED
    var slot := 0

    while slot < active_indices.size():
        var index := active_indices[slot]

        if contact_flags[index] != 0 and velocities[index].length_squared() <= sleep_speed_squared:
            sleep_times[index] += dt
            if sleep_times[index] >= SLEEP_DELAY:
                _sleep(index)
                continue
        else:
            sleep_times[index] = 0.0

        slot += 1

func apply_radial_impulse(center: Vector3, radius: float = 2.7, impulse_speed: float = 8.5) -> void:
    var radius_squared := radius * radius
    var min_coords := _cell_coords_for_position(center - Vector3.ONE * radius)
    var max_coords := _cell_coords_for_position(center + Vector3.ONE * radius)

    for cy in range(min_coords.y, max_coords.y + 1):
        for cz in range(min_coords.z, max_coords.z + 1):
            for cx in range(min_coords.x, max_coords.x + 1):
                var cell := _flat_cell(cx, cy, cz)
                var index := cell_heads[cell]

                while index >= 0:
                    var next_index := next_in_cell[index]
                    var offset := positions[index] - center
                    var distance_squared := offset.length_squared()

                    if distance_squared < radius_squared:
                        var distance := sqrt(maxf(distance_squared, 0.000001))
                        var direction := offset / distance
                        var falloff := pow(1.0 - distance / radius, 1.25)
                        var delta_velocity := impulse_speed * (0.12 + 0.88 * falloff)

                        _wake(index)
                        velocities[index] += direction * delta_velocity
                        _mark_dirty(index)

                    index = next_index

func interact_sphere(
    center: Vector3,
    radius: float,
    body_velocity: Vector3,
    _body_mass: float,
    _dt: float
) -> Vector3:
    var reaction_impulse := Vector3.ZERO
    var minimum_distance := radius + GRAIN_RADIUS
    var minimum_distance_squared := minimum_distance * minimum_distance

    var min_coords := _cell_coords_for_position(center - Vector3.ONE * minimum_distance)
    var max_coords := _cell_coords_for_position(center + Vector3.ONE * minimum_distance)

    for cy in range(min_coords.y, max_coords.y + 1):
        for cz in range(min_coords.z, max_coords.z + 1):
            for cx in range(min_coords.x, max_coords.x + 1):
                var cell := _flat_cell(cx, cy, cz)
                var index := cell_heads[cell]

                while index >= 0:
                    var next_index := next_in_cell[index]
                    var offset := positions[index] - center
                    var distance_squared := offset.length_squared()

                    if distance_squared < minimum_distance_squared:
                        var normal: Vector3
                        var distance: float

                        if distance_squared < 0.00000001:
                            normal = Vector3.UP
                            distance = 0.0001
                        else:
                            distance = sqrt(distance_squared)
                            normal = offset / distance

                        _wake(index)
                        contact_flags[index] = 1

                        var penetration := minimum_distance - distance
                        positions[index] += normal * penetration * 0.92

                        var grain_velocity := velocities[index]
                        var closing_speed := (body_velocity - grain_velocity).dot(normal)

                        if closing_speed > 0.0:
                            var transfer_delta_velocity := normal * closing_speed * 0.68
                            grain_velocity += transfer_delta_velocity
                            reaction_impulse -= transfer_delta_velocity * GRAIN_MASS

                        velocities[index] = grain_velocity
                        _move_particle_cell_if_needed(index)
                        _mark_dirty(index)

                    index = next_index

    return reaction_impulse

func _cell_coords_for_position(position: Vector3) -> Vector3i:
    var x := clampi(
        int(floor((position.x + BOUNDARY_HALF_EXTENT) / CELL_SIZE)),
        0,
        grid_x - 1
    )
    var y := clampi(int(floor(position.y / CELL_SIZE)), 0, GRID_Y_CELLS - 1)
    var z := clampi(
        int(floor((position.z + BOUNDARY_HALF_EXTENT) / CELL_SIZE)),
        0,
        grid_z - 1
    )
    return Vector3i(x, y, z)

func _cell_for_position(position: Vector3) -> int:
    var coords := _cell_coords_for_position(position)
    return _flat_cell(coords.x, coords.y, coords.z)

func _flat_cell(x: int, y: int, z: int) -> int:
    return (y * grid_z + z) * grid_x + x

func _insert_particle_into_cell(index: int, cell: int) -> void:
    var head := cell_heads[cell]

    particle_cell[index] = cell
    prev_in_cell[index] = -1
    next_in_cell[index] = head

    if head >= 0:
        prev_in_cell[head] = index

    cell_heads[cell] = index

func _remove_particle_from_cell(index: int) -> void:
    var cell := particle_cell[index]
    if cell < 0:
        return

    var previous := prev_in_cell[index]
    var next := next_in_cell[index]

    if previous >= 0:
        next_in_cell[previous] = next
    else:
        cell_heads[cell] = next

    if next >= 0:
        prev_in_cell[next] = previous

    prev_in_cell[index] = -1
    next_in_cell[index] = -1
    particle_cell[index] = -1

func _move_particle_cell_if_needed(index: int) -> void:
    var new_cell := _cell_for_position(positions[index])
    if new_cell == particle_cell[index]:
        return

    _remove_particle_from_cell(index)
    _insert_particle_into_cell(index, new_cell)

func surface_height_at(_world_position: Vector3) -> float:
    return PLAYER_SURFACE_Y

func clamp_inside(world_position: Vector3) -> Vector3:
    # The player's capsule and the grains share the same world boundary.
    var player_radius := 0.30
    var limit := BOUNDARY_HALF_EXTENT - player_radius
    world_position.x = clampf(world_position.x, -limit, limit)
    world_position.z = clampf(world_position.z, -limit, limit)
    return world_position

func grain_count() -> int:
    return PARTICLE_COUNT

func active_grain_count() -> int:
    return active_indices.size()

func world_size() -> float:
    return BOUNDARY_HALF_EXTENT * 2.0

func _update_all_visuals() -> void:
    if multimesh == null:
        return

    for i in range(PARTICLE_COUNT):
        multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
        dirty_flags[i] = 0

    dirty_indices.clear()

func _update_dirty_visuals() -> void:
    if multimesh == null or dirty_indices.is_empty():
        return

    for index in dirty_indices:
        multimesh.set_instance_transform(
            index,
            Transform3D(Basis.IDENTITY, positions[index])
        )
        dirty_flags[index] = 0

    dirty_indices.clear()
