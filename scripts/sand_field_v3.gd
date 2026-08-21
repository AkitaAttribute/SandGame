class_name SandFieldV3
extends SandFieldV2

# The requested layout is a 25 x 25 grid of colored regions. Each region keeps
# the original 16 x 16 horizontal grain footprint and is five grains deep.
const REGION_GRID := 25
const REGION_GRAINS := 16
const LARGE_AXIS := REGION_GRID * REGION_GRAINS
const LARGE_LAYERS := 5
const LARGE_LAYER_STRIDE := LARGE_AXIS * LARGE_AXIS
const LARGE_PARTICLE_COUNT := LARGE_LAYER_STRIDE * LARGE_LAYERS

const LARGE_BED_HALF_EXTENT := (
    float(LARGE_AXIS - 1) * PACKING_SPACING * 0.5
)
const LARGE_BOUNDARY_HALF_EXTENT := LARGE_BED_HALF_EXTENT + GRAIN_RADIUS
const LARGE_PLAYER_SURFACE_Y := (
    GRAIN_RADIUS * 2.0 + float(LARGE_LAYERS - 1) * PACKING_SPACING
)

# The large bed is shallow, so a 2D X/Z broadphase is substantially cheaper
# than allocating millions of empty 3D grid cells. Height is still tested by
# the actual sphere/sphere distance check.
const LARGE_GRID_X := int(
    ceil((LARGE_BOUNDARY_HALF_EXTENT * 2.0) / CELL_SIZE)
) + 2
const LARGE_GRID_Z := LARGE_GRID_X
const LARGE_GRID_CELL_COUNT := LARGE_GRID_X * LARGE_GRID_Z
const LARGE_MAX_CELL_PARTICLES := 48

const LARGE_WORKGROUP_SIZE := 128
const LARGE_PBD_ITERATIONS := 5
const LARGE_MAX_COMMANDS := 32
const POSITION_TEXTURE_WIDTH := 1024
const POSITION_TEXTURE_HEIGHT := int(
    ceil(float(LARGE_PARTICLE_COUNT) / float(POSITION_TEXTURE_WIDTH))
)
const SURFACE_COUNT := LARGE_LAYER_STRIDE
const SURFACE_READBACK_INTERVAL := 4

const BODY_SUPPORT_BIAS := 0.34
const BODY_SUPPORT_FRICTION := 0.78
const BODY_SUPPORT_MAX_IMPULSE := 2.8

var main_rd: RenderingDevice
var large_shader_rid := RID()
var large_pipeline_rid := RID()
var large_uniform_set_rid := RID()

var large_position_buffer := RID()
var large_previous_position_buffer := RID()
var large_velocity_buffer := RID()
var large_correction_buffer := RID()
var large_cell_count_buffer := RID()
var large_cell_particle_buffer := RID()
var large_command_buffer := RID()
var large_surface_buffer := RID()

var main_position_texture_rid := RID()
var local_position_texture_rid := RID()
var position_texture_resource: Texture2DRD

var large_multimesh_instance: MultiMeshInstance3D
var large_multimesh: MultiMesh
var large_render_material: ShaderMaterial

var large_commands: Array = []
var large_simulation_accumulator := 0.0
var surface_cache := PackedFloat32Array()
var surface_read_counter := 0
var surface_read_pending := false

func _ready() -> void:
    add_to_group("sand")

    surface_cache.resize(SURFACE_COUNT)
    surface_cache.fill(LARGE_PLAYER_SURFACE_Y)

    # CI/headless runs validate scripts and shaders without allocating the
    # 800k-instance render resources.
    if OS.has_feature("headless"):
        return

    _build_large_multimesh()
    _initialize_large_gpu_solver()

func _exit_tree() -> void:
    if rd != null:
        for rid in [
            large_uniform_set_rid,
            large_pipeline_rid,
            large_shader_rid,
            large_position_buffer,
            large_previous_position_buffer,
            large_velocity_buffer,
            large_correction_buffer,
            large_cell_count_buffer,
            large_cell_particle_buffer,
            large_command_buffer,
            large_surface_buffer,
            local_position_texture_rid,
        ]:
            if rid.is_valid():
                rd.free_rid(rid)

    if position_texture_resource != null:
        position_texture_resource.texture_rd_rid = RID()

    if main_rd != null and main_position_texture_rid.is_valid():
        main_rd.free_rid(main_position_texture_rid)

func _physics_process(delta: float) -> void:
    if not gpu_ready:
        return

    large_simulation_accumulator += minf(delta, 0.05)
    var steps := 0

    while (
        large_simulation_accumulator >= SIM_DT
        and steps < MAX_SIM_STEPS_PER_FRAME
    ):
        _run_large_gpu_step()
        large_simulation_accumulator -= SIM_DT
        steps += 1

    if (
        steps >= MAX_SIM_STEPS_PER_FRAME
        and large_simulation_accumulator > SIM_DT
    ):
        large_simulation_accumulator = SIM_DT

func _build_large_multimesh() -> void:
    large_multimesh_instance = MultiMeshInstance3D.new()
    large_multimesh_instance.name = "LargeSimulatedSandGrains"
    large_multimesh_instance.cast_shadow = (
        GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    )
    add_child(large_multimesh_instance)

    var sphere := SphereMesh.new()
    sphere.radius = GRAIN_RADIUS
    sphere.height = GRAIN_DIAMETER
    sphere.radial_segments = 4
    sphere.rings = 2

    var render_shader := load("res://shaders/sand_render.gdshader") as Shader
    large_render_material = ShaderMaterial.new()
    large_render_material.shader = render_shader
    large_render_material.set_shader_parameter(
        "position_texture_width",
        POSITION_TEXTURE_WIDTH
    )
    large_render_material.set_shader_parameter("axis_particles", LARGE_AXIS)
    large_render_material.set_shader_parameter("region_size", REGION_GRAINS)
    sphere.material = large_render_material

    large_multimesh = MultiMesh.new()
    large_multimesh.transform_format = MultiMesh.TRANSFORM_3D
    large_multimesh.mesh = sphere
    large_multimesh.instance_count = LARGE_PARTICLE_COUNT

    # Instances never move through the MultiMesh transform buffer. The vertex
    # shader fetches each grain position directly from the compute texture.
    # Populate identity transforms once and never upload this buffer again.
    var identity_buffer := PackedFloat32Array()
    identity_buffer.resize(LARGE_PARTICLE_COUNT * 12)
    for i in range(LARGE_PARTICLE_COUNT):
        var base := i * 12
        identity_buffer[base + 0] = 1.0
        identity_buffer[base + 5] = 1.0
        identity_buffer[base + 10] = 1.0
    large_multimesh.buffer = identity_buffer

    large_multimesh.custom_aabb = AABB(
        Vector3(-LARGE_BOUNDARY_HALF_EXTENT, -1.0, -LARGE_BOUNDARY_HALF_EXTENT),
        Vector3(
            LARGE_BOUNDARY_HALF_EXTENT * 2.0,
            42.0,
            LARGE_BOUNDARY_HALF_EXTENT * 2.0
        )
    )
    large_multimesh_instance.multimesh = large_multimesh

func _initialize_large_gpu_solver() -> void:
    main_rd = RenderingServer.get_rendering_device()
    rd = RenderingServer.create_local_rendering_device()
    if main_rd == null or rd == null:
        push_error("RenderingDevice unavailable; large sand solver disabled.")
        return

    var texture_format := RDTextureFormat.new()
    texture_format.width = POSITION_TEXTURE_WIDTH
    texture_format.height = POSITION_TEXTURE_HEIGHT
    texture_format.depth = 1
    texture_format.array_layers = 1
    texture_format.mipmaps = 1
    texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
    texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    texture_format.usage_bits = (
        RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
        | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
        | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
        | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
    )

    main_position_texture_rid = main_rd.texture_create(
        texture_format,
        RDTextureView.new(),
        []
    )
    if not main_position_texture_rid.is_valid():
        push_error("Unable to create shared sand position texture.")
        return

    position_texture_resource = Texture2DRD.new()
    position_texture_resource.texture_rd_rid = main_position_texture_rid
    large_render_material.set_shader_parameter(
        "position_texture",
        position_texture_resource
    )

    var native_texture := main_rd.get_driver_resource(
        RenderingDevice.DRIVER_RESOURCE_TEXTURE,
        main_position_texture_rid,
        0
    )
    local_position_texture_rid = rd.texture_create_from_extension(
        RenderingDevice.TEXTURE_TYPE_2D,
        texture_format.format,
        texture_format.samples,
        texture_format.usage_bits,
        native_texture,
        texture_format.width,
        texture_format.height,
        texture_format.depth,
        texture_format.array_layers,
        texture_format.mipmaps
    )
    if not local_position_texture_rid.is_valid():
        push_error("Unable to share sand position texture with compute device.")
        return

    var shader_file := load("res://shaders/sand_pbd_large.glsl") as RDShaderFile
    if shader_file == null:
        push_error("Unable to load large sand compute shader.")
        return

    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    large_shader_rid = rd.shader_create_from_spirv(spirv)
    if not large_shader_rid.is_valid():
        push_error("Unable to create large sand compute shader.")
        return

    large_pipeline_rid = rd.compute_pipeline_create(large_shader_rid)
    if not large_pipeline_rid.is_valid():
        push_error("Unable to create large sand compute pipeline.")
        return

    var particle_bytes := LARGE_PARTICLE_COUNT * 16
    large_position_buffer = rd.storage_buffer_create(particle_bytes)
    large_previous_position_buffer = rd.storage_buffer_create(particle_bytes)
    large_velocity_buffer = rd.storage_buffer_create(particle_bytes)
    large_correction_buffer = rd.storage_buffer_create(particle_bytes)
    large_cell_count_buffer = rd.storage_buffer_create(
        LARGE_GRID_CELL_COUNT * 4
    )
    large_cell_particle_buffer = rd.storage_buffer_create(
        LARGE_GRID_CELL_COUNT * LARGE_MAX_CELL_PARTICLES * 4
    )
    large_command_buffer = rd.storage_buffer_create(LARGE_MAX_COMMANDS * 8 * 4)
    large_surface_buffer = rd.storage_buffer_create(SURFACE_COUNT * 4)

    var uniforms: Array[RDUniform] = []
    uniforms.append(_large_storage_uniform(0, large_position_buffer))
    uniforms.append(_large_storage_uniform(1, large_previous_position_buffer))
    uniforms.append(_large_storage_uniform(2, large_velocity_buffer))
    uniforms.append(_large_storage_uniform(3, large_correction_buffer))
    uniforms.append(_large_storage_uniform(4, large_cell_count_buffer))
    uniforms.append(_large_storage_uniform(5, large_cell_particle_buffer))
    uniforms.append(_large_storage_uniform(6, large_command_buffer))

    var image_uniform := RDUniform.new()
    image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    image_uniform.binding = 7
    image_uniform.add_id(local_position_texture_rid)
    uniforms.append(image_uniform)
    uniforms.append(_large_storage_uniform(8, large_surface_buffer))

    large_uniform_set_rid = rd.uniform_set_create(
        uniforms,
        large_shader_rid,
        0
    )
    if not large_uniform_set_rid.is_valid():
        push_error("Unable to create large sand compute uniform set.")
        return

    _initialize_large_particle_state()
    gpu_ready = true
    _request_surface_readback()

func _large_storage_uniform(binding: int, rid: RID) -> RDUniform:
    var uniform := RDUniform.new()
    uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform.binding = binding
    uniform.add_id(rid)
    return uniform

func _initialize_large_particle_state() -> void:
    var particle_groups := _groups_for(LARGE_PARTICLE_COUNT)
    var surface_groups := _groups_for(SURFACE_COUNT)
    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, large_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, large_uniform_set_rid, 0)

    _dispatch_large_phase(compute_list, 6, particle_groups, 0, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_large_phase(compute_list, 7, surface_groups, 0, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_large_phase(compute_list, 8, particle_groups, 0, 0)

    rd.compute_list_end()
    rd.submit()
    rd.sync()

func _run_large_gpu_step() -> void:
    _upload_large_commands()

    var particle_groups := _groups_for(LARGE_PARTICLE_COUNT)
    var grid_groups := _groups_for(LARGE_GRID_CELL_COUNT)
    var surface_groups := _groups_for(SURFACE_COUNT)
    var command_count := mini(large_commands.size(), LARGE_MAX_COMMANDS)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, large_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, large_uniform_set_rid, 0)

    _dispatch_large_phase(compute_list, 0, particle_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)

    for iteration in range(LARGE_PBD_ITERATIONS):
        _dispatch_large_phase(compute_list, 1, grid_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_large_phase(compute_list, 2, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_large_phase(compute_list, 3, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_large_phase(compute_list, 4, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)

    _dispatch_large_phase(compute_list, 5, particle_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_large_phase(compute_list, 7, surface_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_large_phase(compute_list, 8, particle_groups, command_count, 0)

    rd.compute_list_end()
    rd.submit()
    # The local compute device and the main renderer share the position image.
    # Synchronize the compute write before the renderer samples that image.
    rd.sync()

    large_commands.clear()
    surface_read_counter += 1
    if surface_read_counter >= SURFACE_READBACK_INTERVAL:
        surface_read_counter = 0
        _request_surface_readback()

func _groups_for(count: int) -> int:
    return int(ceil(float(count) / float(LARGE_WORKGROUP_SIZE)))

func _dispatch_large_phase(
    compute_list: int,
    phase: int,
    groups: int,
    command_count: int,
    iteration: int
) -> void:
    var push := _make_large_push_constants(phase, command_count, iteration)
    rd.compute_list_set_push_constant(compute_list, push, push.size())
    rd.compute_list_dispatch(compute_list, groups, 1, 1)

func _make_large_push_constants(
    phase: int,
    command_count: int,
    iteration: int
) -> PackedByteArray:
    var push := PackedByteArray()
    push.resize(80)

    push.encode_u32(0, phase)
    push.encode_u32(4, LARGE_PARTICLE_COUNT)
    push.encode_u32(8, LARGE_GRID_X)
    push.encode_u32(12, LARGE_GRID_Z)
    push.encode_u32(16, LARGE_MAX_CELL_PARTICLES)
    push.encode_u32(20, command_count)
    push.encode_u32(24, iteration)
    push.encode_u32(28, LARGE_AXIS)

    push.encode_float(32, SIM_DT)
    push.encode_float(36, GRAIN_RADIUS)
    push.encode_float(40, LARGE_BOUNDARY_HALF_EXTENT)
    push.encode_float(44, CELL_SIZE)
    push.encode_float(48, GRAVITY)
    push.encode_float(52, PACKED_GRAIN_FRICTION)
    push.encode_float(56, RESTITUTION)
    push.encode_float(60, VELOCITY_DAMPING)

    push.encode_float(64, PACKING_SPACING)
    push.encode_u32(68, POSITION_TEXTURE_WIDTH)
    push.encode_u32(72, SURFACE_COUNT)
    push.encode_u32(76, REGION_GRAINS)
    return push

func _upload_large_commands() -> void:
    var data := PackedFloat32Array()
    data.resize(LARGE_MAX_COMMANDS * 8)
    var count := mini(large_commands.size(), LARGE_MAX_COMMANDS)

    for i in range(count):
        var command: Dictionary = large_commands[i]
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
    rd.buffer_update(large_command_buffer, 0, bytes.size(), bytes)

func _queue_large_command(
    center: Vector3,
    radius: float,
    vector: Vector3,
    mode: float
) -> void:
    if not gpu_ready or large_commands.size() >= LARGE_MAX_COMMANDS:
        return
    large_commands.append({
        "center": center,
        "radius": radius,
        "vector": vector,
        "mode": mode,
    })

func _request_surface_readback() -> void:
    if rd == null or not large_surface_buffer.is_valid() or surface_read_pending:
        return
    surface_read_pending = true
    var error := rd.buffer_get_data_async(
        large_surface_buffer,
        _on_surface_readback
    )
    if error != OK:
        surface_read_pending = false

func _on_surface_readback(data: PackedByteArray) -> void:
    surface_read_pending = false
    var values := data.to_float32_array()
    if values.size() >= SURFACE_COUNT:
        surface_cache = values

func apply_radial_impulse(
    center: Vector3,
    radius: float = 2.7,
    impulse_speed: float = 12.5
) -> void:
    _queue_large_command(
        center,
        radius,
        Vector3(impulse_speed, 0.0, 0.0),
        1.0
    )

func interact_sphere(
    center: Vector3,
    radius: float,
    body_velocity: Vector3,
    body_mass: float,
    dt: float
) -> Vector3:
    _queue_large_command(center, radius, body_velocity, 2.0)

    # Use the GPU-derived local granular surface as the body's support contact.
    # This avoids scanning 800k positions on the CPU while still following
    # craters and piles produced by the actual grain simulation.
    var surface_y := surface_height_at(center)
    var penetration := surface_y - (center.y - radius)
    if penetration <= 0.0:
        return Vector3.ZERO

    var safe_dt := maxf(dt, 1.0 / 240.0)
    var downward_speed := maxf(0.0, -body_velocity.y)
    var correction_speed := minf(
        penetration / safe_dt * BODY_SUPPORT_BIAS,
        5.0
    )
    var normal_impulse := body_mass * (
        downward_speed * 0.92
        + correction_speed
        + GRAVITY * safe_dt
    )
    normal_impulse = minf(normal_impulse, BODY_SUPPORT_MAX_IMPULSE)

    var reaction := Vector3.UP * normal_impulse
    var lateral := Vector3(body_velocity.x, 0.0, body_velocity.z)
    var lateral_speed := lateral.length()
    if lateral_speed > 0.0001:
        var friction_impulse := minf(
            body_mass * lateral_speed * 0.16,
            normal_impulse * BODY_SUPPORT_FRICTION
        )
        reaction -= lateral / lateral_speed * friction_impulse
    return reaction

func interact_foot(
    center: Vector3,
    radius: float,
    travel_velocity: Vector3
) -> void:
    var flat_velocity := Vector3(travel_velocity.x, 0.0, travel_velocity.z)
    _queue_large_command(center, radius, flat_velocity, 3.0)

func surface_height_at(world_position: Vector3) -> float:
    if surface_cache.is_empty():
        return LARGE_PLAYER_SURFACE_Y

    var min_center := -LARGE_BED_HALF_EXTENT
    var center_x := int(round(
        (world_position.x - min_center) / PACKING_SPACING
    ))
    var center_z := int(round(
        (world_position.z - min_center) / PACKING_SPACING
    ))

    var highest := 0.0
    for oz in range(-1, 2):
        var z := center_z + oz
        if z < 0 or z >= LARGE_AXIS:
            continue
        for ox in range(-1, 2):
            var x := center_x + ox
            if x < 0 or x >= LARGE_AXIS:
                continue
            highest = maxf(highest, surface_cache[z * LARGE_AXIS + x])

    if highest <= 0.0001:
        return 0.0

    var total := 0.0
    var count := 0
    var minimum_top := highest - GRAIN_RADIUS * 0.90
    for oz in range(-1, 2):
        var z := center_z + oz
        if z < 0 or z >= LARGE_AXIS:
            continue
        for ox in range(-1, 2):
            var x := center_x + ox
            if x < 0 or x >= LARGE_AXIS:
                continue
            var height := surface_cache[z * LARGE_AXIS + x]
            if height >= minimum_top:
                total += height
                count += 1

    return highest if count == 0 else total / float(count)

func clamp_inside(world_position: Vector3) -> Vector3:
    var player_radius := 0.30
    var limit := LARGE_BOUNDARY_HALF_EXTENT - player_radius
    world_position.x = clampf(world_position.x, -limit, limit)
    world_position.z = clampf(world_position.z, -limit, limit)
    return world_position

func grain_count() -> int:
    return LARGE_PARTICLE_COUNT

func active_grain_count() -> int:
    return LARGE_PARTICLE_COUNT if gpu_ready else 0

func world_size() -> float:
    return LARGE_BOUNDARY_HALF_EXTENT * 2.0

func solver_name() -> String:
    if not gpu_ready:
        return "GPU PBD 800k unavailable"
    return "GPU PBD 800k / 25x25 regions / 5 deep"
