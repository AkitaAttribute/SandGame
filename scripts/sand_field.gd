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
const GRID_X_CELLS := int(ceil((BOUNDARY_HALF_EXTENT * 2.0) / CELL_SIZE)) + 2
const GRID_Z_CELLS := GRID_X_CELLS
const GRID_CELL_COUNT := GRID_X_CELLS * GRID_Y_CELLS * GRID_Z_CELLS
const MAX_CELL_PARTICLES := 24

const SIM_HZ := 60.0
const SIM_DT := 1.0 / SIM_HZ
const MAX_SIM_STEPS_PER_FRAME := 2
const PBD_ITERATIONS := 5
const WORKGROUP_SIZE := 128
const MAX_COMMANDS := 16

const CONTACT_FRICTION := 0.48
const RESTITUTION := 0.04
const VELOCITY_DAMPING := 0.997
const CONTACT_BIAS_PER_SECOND := 25.0
const MAX_BODY_REACTION_IMPULSE := 0.85

const PALETTE := [
    Color(0.86, 0.18, 0.15),
    Color(0.15, 0.38, 0.92),
    Color(0.95, 0.79, 0.14),
    Color(0.18, 0.72, 0.31),
]

var rd: RenderingDevice
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_set_rid := RID()

var position_buffer := RID()
var previous_position_buffer := RID()
var velocity_buffer := RID()
var correction_buffer := RID()
var cell_count_buffer := RID()
var cell_particle_buffer := RID()
var command_buffer := RID()

var cpu_positions := PackedVector3Array()
var cpu_previous_positions := PackedVector3Array()
var colors := PackedInt32Array()

var pending_commands: Array = []
var simulation_accumulator := 0.0
var gpu_ready := false

var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh
var render_buffer := PackedFloat32Array()

func _ready() -> void:
    add_to_group("sand")
    _initialize_particles()
    _build_multimesh()

    if not OS.has_feature("headless"):
        _initialize_gpu_solver()

    _update_render_buffer()

func _exit_tree() -> void:
    if rd == null:
        return

    for rid in [
        uniform_set_rid,
        pipeline_rid,
        shader_rid,
        position_buffer,
        previous_position_buffer,
        velocity_buffer,
        correction_buffer,
        cell_count_buffer,
        cell_particle_buffer,
        command_buffer,
    ]:
        if rid.is_valid():
            rd.free_rid(rid)

func _physics_process(delta: float) -> void:
    if not gpu_ready:
        return

    simulation_accumulator += minf(delta, 0.05)
    var steps := 0

    while simulation_accumulator >= SIM_DT and steps < MAX_SIM_STEPS_PER_FRAME:
        _run_gpu_step()
        simulation_accumulator -= SIM_DT
        steps += 1

    if steps >= MAX_SIM_STEPS_PER_FRAME and simulation_accumulator > SIM_DT:
        simulation_accumulator = SIM_DT

func _initialize_particles() -> void:
    cpu_positions.resize(PARTICLE_COUNT)
    cpu_previous_positions.resize(PARTICLE_COUNT)
    colors.resize(PARTICLE_COUNT)

    var index := 0
    for layer in range(LAYERS):
        for z in range(PARTICLES_Z):
            for x in range(PARTICLES_X):
                var px := (
                    (float(x) - float(PARTICLES_X - 1) * 0.5)
                    * PACKING_SPACING
                )
                var pz := (
                    (float(z) - float(PARTICLES_Z - 1) * 0.5)
                    * PACKING_SPACING
                )
                var py := GRAIN_RADIUS + float(layer) * PACKING_SPACING
                var position := Vector3(px, py, pz)

                cpu_positions[index] = position
                cpu_previous_positions[index] = position
                colors[index] = _initial_color_index(position)
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

    render_buffer.resize(PARTICLE_COUNT * 16)

    for i in range(PARTICLE_COUNT):
        var base := i * 16
        render_buffer[base + 0] = 1.0
        render_buffer[base + 1] = 0.0
        render_buffer[base + 2] = 0.0
        render_buffer[base + 4] = 0.0
        render_buffer[base + 5] = 1.0
        render_buffer[base + 6] = 0.0
        render_buffer[base + 8] = 0.0
        render_buffer[base + 9] = 0.0
        render_buffer[base + 10] = 1.0

        var color: Color = PALETTE[colors[i]]
        render_buffer[base + 12] = color.r
        render_buffer[base + 13] = color.g
        render_buffer[base + 14] = color.b
        render_buffer[base + 15] = 1.0

func _initialize_gpu_solver() -> void:
    rd = RenderingServer.create_local_rendering_device()
    if rd == null:
        push_warning("RenderingDevice unavailable; sand GPU solver disabled.")
        return

    var shader_file := load("res://shaders/sand_pbd.glsl") as RDShaderFile
    if shader_file == null:
        push_error("Unable to load sand compute shader.")
        return

    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    shader_rid = rd.shader_create_from_spirv(spirv)
    if not shader_rid.is_valid():
        push_error("Unable to create sand compute shader.")
        return

    pipeline_rid = rd.compute_pipeline_create(shader_rid)
    if not pipeline_rid.is_valid():
        push_error("Unable to create sand compute pipeline.")
        return

    var position_data := PackedFloat32Array()
    position_data.resize(PARTICLE_COUNT * 4)

    for i in range(PARTICLE_COUNT):
        var p := cpu_positions[i]
        var base := i * 4
        position_data[base + 0] = p.x
        position_data[base + 1] = p.y
        position_data[base + 2] = p.z
        position_data[base + 3] = 1.0

    var zero_vectors := PackedFloat32Array()
    zero_vectors.resize(PARTICLE_COUNT * 4)

    var position_bytes := position_data.to_byte_array()
    var zero_vector_bytes := zero_vectors.to_byte_array()

    position_buffer = rd.storage_buffer_create(
        position_bytes.size(),
        position_bytes
    )
    previous_position_buffer = rd.storage_buffer_create(
        position_bytes.size(),
        position_bytes
    )
    velocity_buffer = rd.storage_buffer_create(
        zero_vector_bytes.size(),
        zero_vector_bytes
    )
    correction_buffer = rd.storage_buffer_create(
        zero_vector_bytes.size(),
        zero_vector_bytes
    )

    var zero_counts := PackedInt32Array()
    zero_counts.resize(GRID_CELL_COUNT)
    var zero_count_bytes := zero_counts.to_byte_array()
    cell_count_buffer = rd.storage_buffer_create(
        zero_count_bytes.size(),
        zero_count_bytes
    )

    var cell_slots := PackedInt32Array()
    cell_slots.resize(GRID_CELL_COUNT * MAX_CELL_PARTICLES)
    var cell_slot_bytes := cell_slots.to_byte_array()
    cell_particle_buffer = rd.storage_buffer_create(
        cell_slot_bytes.size(),
        cell_slot_bytes
    )

    var command_data := PackedFloat32Array()
    command_data.resize(MAX_COMMANDS * 8)
    var command_bytes := command_data.to_byte_array()
    command_buffer = rd.storage_buffer_create(
        command_bytes.size(),
        command_bytes
    )

    var uniforms: Array[RDUniform] = []
    uniforms.append(_storage_uniform(0, position_buffer))
    uniforms.append(_storage_uniform(1, previous_position_buffer))
    uniforms.append(_storage_uniform(2, velocity_buffer))
    uniforms.append(_storage_uniform(3, correction_buffer))
    uniforms.append(_storage_uniform(4, cell_count_buffer))
    uniforms.append(_storage_uniform(5, cell_particle_buffer))
    uniforms.append(_storage_uniform(6, command_buffer))

    uniform_set_rid = rd.uniform_set_create(uniforms, shader_rid, 0)
    if not uniform_set_rid.is_valid():
        push_error("Unable to create sand compute uniform set.")
        return

    gpu_ready = true

func _storage_uniform(binding: int, rid: RID) -> RDUniform:
    var uniform := RDUniform.new()
    uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform.binding = binding
    uniform.add_id(rid)
    return uniform

func _run_gpu_step() -> void:
    _upload_pending_commands()

    var particle_groups := int(ceil(float(PARTICLE_COUNT) / float(WORKGROUP_SIZE)))
    var grid_groups := int(ceil(float(GRID_CELL_COUNT) / float(WORKGROUP_SIZE)))
    var command_count := mini(pending_commands.size(), MAX_COMMANDS)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)

    _dispatch_phase(compute_list, 0, particle_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)

    for iteration in range(PBD_ITERATIONS):
        _dispatch_phase(compute_list, 1, grid_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)

        _dispatch_phase(compute_list, 2, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)

        _dispatch_phase(compute_list, 3, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)

        _dispatch_phase(compute_list, 4, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)

    _dispatch_phase(compute_list, 5, particle_groups, command_count, 0)

    rd.compute_list_end()
    rd.submit()
    rd.sync()

    pending_commands.clear()
    _read_back_positions()
    _update_render_buffer()

func _dispatch_phase(
    compute_list: int,
    phase: int,
    groups: int,
    command_count: int,
    iteration: int
) -> void:
    var push := _make_push_constants(phase, command_count, iteration)
    rd.compute_list_set_push_constant(compute_list, push, push.size())
    rd.compute_list_dispatch(compute_list, groups, 1, 1)

func _make_push_constants(
    phase: int,
    command_count: int,
    iteration: int
) -> PackedByteArray:
    var push := PackedByteArray()
    push.resize(64)

    push.encode_u32(0, phase)
    push.encode_u32(4, PARTICLE_COUNT)
    push.encode_u32(8, GRID_X_CELLS)
    push.encode_u32(12, GRID_Y_CELLS)
    push.encode_u32(16, GRID_Z_CELLS)
    push.encode_u32(20, MAX_CELL_PARTICLES)
    push.encode_u32(24, command_count)
    push.encode_u32(28, iteration)

    push.encode_float(32, SIM_DT)
    push.encode_float(36, GRAIN_RADIUS)
    push.encode_float(40, BOUNDARY_HALF_EXTENT)
    push.encode_float(44, CELL_SIZE)
    push.encode_float(48, GRAVITY)
    push.encode_float(52, CONTACT_FRICTION)
    push.encode_float(56, RESTITUTION)
    push.encode_float(60, VELOCITY_DAMPING)

    return push

func _upload_pending_commands() -> void:
    var data := PackedFloat32Array()
    data.resize(MAX_COMMANDS * 8)

    var count := mini(pending_commands.size(), MAX_COMMANDS)
    for i in range(count):
        var command: Dictionary = pending_commands[i]
        var center: Vector3 = command["center"]
        var vector: Vector3 = command["vector"]
        var base := i * 8

        data[base + 0] = center.x
        data[base + 1] = center.y
        data[base + 2] = center.z
        data[base + 3] = float(command["radius"])
        data[base + 4] = vector.x
        data[base + 5] = vector.y
        data[base + 6] = vector.z
        data[base + 7] = float(command["mode"])

    var bytes := data.to_byte_array()
    rd.buffer_update(command_buffer, 0, bytes.size(), bytes)

func _read_back_positions() -> void:
    var bytes := rd.buffer_get_data(position_buffer)
    var values := bytes.to_float32_array()
    if values.size() < PARTICLE_COUNT * 4:
        return

    cpu_previous_positions = cpu_positions.duplicate()

    for i in range(PARTICLE_COUNT):
        var base := i * 4
        cpu_positions[i] = Vector3(
            values[base + 0],
            values[base + 1],
            values[base + 2]
        )

func _update_render_buffer() -> void:
    if multimesh == null:
        return

    for i in range(PARTICLE_COUNT):
        var p := cpu_positions[i]
        var base := i * 16
        render_buffer[base + 3] = p.x
        render_buffer[base + 7] = p.y
        render_buffer[base + 11] = p.z

    RenderingServer.multimesh_set_buffer(multimesh.get_rid(), render_buffer)

func apply_radial_impulse(
    center: Vector3,
    radius: float = 2.7,
    impulse_speed: float = 8.5
) -> void:
    _queue_command(center, radius, Vector3(impulse_speed, 0.0, 0.0), 1.0)

func interact_sphere(
    center: Vector3,
    radius: float,
    body_velocity: Vector3,
    body_mass: float,
    _dt: float
) -> Vector3:
    _queue_command(center, radius, body_velocity, 2.0)

    if cpu_positions.is_empty():
        return Vector3.ZERO

    var reaction_impulse := Vector3.ZERO
    var minimum_distance := radius + GRAIN_RADIUS
    var minimum_distance_squared := minimum_distance * minimum_distance
    var reduced_mass := (
        body_mass * GRAIN_MASS / maxf(body_mass + GRAIN_MASS, 0.0001)
    )

    for i in range(PARTICLE_COUNT):
        var offset := cpu_positions[i] - center
        var distance_squared := offset.length_squared()
        if distance_squared >= minimum_distance_squared:
            continue

        var distance := sqrt(maxf(distance_squared, 0.0000001))
        var normal := offset / distance if distance > 0.0001 else Vector3.DOWN
        var penetration := minimum_distance - distance

        var grain_velocity := (
            (cpu_positions[i] - cpu_previous_positions[i]) / SIM_DT
        )
        var closing_speed := maxf(
            0.0,
            (body_velocity - grain_velocity).dot(normal)
        )
        var bias_speed := penetration * CONTACT_BIAS_PER_SECOND

        var impulse_magnitude := reduced_mass * (
            closing_speed * (1.0 + RESTITUTION) + bias_speed
        )
        reaction_impulse -= normal * impulse_magnitude

    if reaction_impulse.length() > MAX_BODY_REACTION_IMPULSE:
        reaction_impulse = (
            reaction_impulse.normalized() * MAX_BODY_REACTION_IMPULSE
        )

    return reaction_impulse

func _queue_command(
    center: Vector3,
    radius: float,
    vector: Vector3,
    mode: float
) -> void:
    if not gpu_ready or pending_commands.size() >= MAX_COMMANDS:
        return

    pending_commands.append({
        "center": center,
        "radius": radius,
        "vector": vector,
        "mode": mode,
    })

func surface_height_at(_world_position: Vector3) -> float:
    return PLAYER_SURFACE_Y

func clamp_inside(world_position: Vector3) -> Vector3:
    var player_radius := 0.30
    var limit := BOUNDARY_HALF_EXTENT - player_radius
    world_position.x = clampf(world_position.x, -limit, limit)
    world_position.z = clampf(world_position.z, -limit, limit)
    return world_position

func grain_count() -> int:
    return PARTICLE_COUNT

func active_grain_count() -> int:
    return PARTICLE_COUNT if gpu_ready else 0

func world_size() -> float:
    return BOUNDARY_HALF_EXTENT * 2.0

func solver_name() -> String:
    return "GPU PBD" if gpu_ready else "GPU PBD unavailable"
