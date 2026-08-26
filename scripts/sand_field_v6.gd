class_name SandFieldV6
extends SandFieldV3

# Per-grain activation replaces region/chunk activation. A grain is either
# locked (state 0) or active with a small propagation budget (states 1..5).
# Direct explosion contact starts at level 5, so motion can traverse at most
# about five grains along any one contact chain before encountering locked sand.
const LOCK_SIM_HZ := 30.0
const LOCK_SIM_DT := 1.0 / LOCK_SIM_HZ
const LOCK_PBD_ITERATIONS := 4
const ACTIVE_COUNT_READ_INTERVAL := 3
const LOCK_SURFACE_READ_INTERVAL := 6

const RENDER_CHUNK_PARTICLES := REGION_GRAINS * REGION_GRAINS * LARGE_LAYERS

var grain_state_buffer := RID()
var grain_sleep_buffer := RID()
var active_count_buffer := RID()
var wake_impulse_buffer := RID()

var full_render_instances: Array[MultiMeshInstance3D] = []
var full_render_materials: Array[ShaderMaterial] = []

var active_count_read_pending := false
var active_count_read_counter := 0
var reported_active_grains := 0
var force_simulation := false

func _ready() -> void:
    add_to_group("sand")

    surface_cache.resize(SURFACE_COUNT)
    surface_cache.fill(LARGE_PLAYER_SURFACE_Y)

    if OS.has_feature("headless"):
        return

    _build_full_grain_rendering()
    _initialize_locked_gpu_solver()

func _exit_tree() -> void:
    if rd != null:
        for rid in [
            grain_state_buffer,
            grain_sleep_buffer,
            active_count_buffer,
            wake_impulse_buffer,
        ]:
            if rid.is_valid():
                rd.free_rid(rid)

    super._exit_tree()

func _physics_process(delta: float) -> void:
    if not gpu_ready:
        return

    if (
        reported_active_grains == 0
        and large_commands.is_empty()
        and not force_simulation
    ):
        large_simulation_accumulator = 0.0
        return

    large_simulation_accumulator += minf(delta, 0.07)
    if large_simulation_accumulator < LOCK_SIM_DT:
        return

    _run_locked_gpu_step()
    large_simulation_accumulator -= LOCK_SIM_DT

    if large_simulation_accumulator > LOCK_SIM_DT:
        large_simulation_accumulator = LOCK_SIM_DT

func _build_full_grain_rendering() -> void:
    # Every grain remains visible. Render-only 16x16 regions exist solely so
    # Godot can frustum-cull off-screen geometry; there is no distance cutoff,
    # replacement plane, or physics meaning attached to these boundaries.
    var render_shader := load("res://shaders/sand_render_chunk.gdshader") as Shader
    if render_shader == null:
        push_error("Unable to load full sand render shader.")
        return

    var sphere := SphereMesh.new()
    sphere.radius = GRAIN_RADIUS
    sphere.height = GRAIN_DIAMETER
    sphere.radial_segments = 4
    sphere.rings = 2

    var identity_buffer := PackedFloat32Array()
    identity_buffer.resize(RENDER_CHUNK_PARTICLES * 12)
    for i in range(RENDER_CHUNK_PARTICLES):
        var base := i * 12
        identity_buffer[base + 0] = 1.0
        identity_buffer[base + 5] = 1.0
        identity_buffer[base + 10] = 1.0

    var minimum_center := -LARGE_BED_HALF_EXTENT
    var region_half := (
        float(REGION_GRAINS - 1) * PACKING_SPACING * 0.5 + GRAIN_RADIUS
    )

    for region_z in range(REGION_GRID):
        for region_x in range(REGION_GRID):
            var center_x := minimum_center + (
                float(region_x * REGION_GRAINS)
                + float(REGION_GRAINS - 1) * 0.5
            ) * PACKING_SPACING
            var center_z := minimum_center + (
                float(region_z * REGION_GRAINS)
                + float(REGION_GRAINS - 1) * 0.5
            ) * PACKING_SPACING

            var material := ShaderMaterial.new()
            material.shader = render_shader
            material.set_shader_parameter(
                "position_texture_width",
                POSITION_TEXTURE_WIDTH
            )
            material.set_shader_parameter("axis_particles", LARGE_AXIS)
            material.set_shader_parameter("region_size", REGION_GRAINS)
            material.set_shader_parameter("region_x", region_x)
            material.set_shader_parameter("region_z", region_z)
            full_render_materials.append(material)

            var multimesh := MultiMesh.new()
            multimesh.transform_format = MultiMesh.TRANSFORM_3D
            multimesh.mesh = sphere
            multimesh.instance_count = RENDER_CHUNK_PARTICLES
            multimesh.buffer = identity_buffer
            multimesh.custom_aabb = AABB(
                Vector3(
                    center_x - region_half,
                    -1.0,
                    center_z - region_half
                ),
                Vector3(region_half * 2.0, 42.0, region_half * 2.0)
            )

            var instance := MultiMeshInstance3D.new()
            instance.name = "SandRender_%02d_%02d" % [region_x, region_z]
            instance.multimesh = multimesh
            instance.material_override = material
            instance.cast_shadow = (
                GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            )
            add_child(instance)
            full_render_instances.append(instance)

func _initialize_locked_gpu_solver() -> void:
    main_rd = RenderingServer.get_rendering_device()
    rd = RenderingServer.create_local_rendering_device()
    if main_rd == null or rd == null:
        push_error("RenderingDevice unavailable; locked grain solver disabled.")
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
        push_error("Unable to create locked grain position texture.")
        return

    position_texture_resource = Texture2DRD.new()
    position_texture_resource.texture_rd_rid = main_position_texture_rid
    for material in full_render_materials:
        material.set_shader_parameter(
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
        push_error("Unable to share locked grain texture with compute device.")
        return

    var shader_file := load(
        "res://shaders/sand_pbd_locked.glsl"
    ) as RDShaderFile
    if shader_file == null:
        push_error("Unable to load locked grain compute shader.")
        return

    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    large_shader_rid = rd.shader_create_from_spirv(spirv)
    if not large_shader_rid.is_valid():
        push_error("Unable to create locked grain compute shader.")
        return

    large_pipeline_rid = rd.compute_pipeline_create(large_shader_rid)
    if not large_pipeline_rid.is_valid():
        push_error("Unable to create locked grain compute pipeline.")
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

    grain_state_buffer = rd.storage_buffer_create(LARGE_PARTICLE_COUNT * 4)
    grain_sleep_buffer = rd.storage_buffer_create(LARGE_PARTICLE_COUNT * 4)
    active_count_buffer = rd.storage_buffer_create(4)
    wake_impulse_buffer = rd.storage_buffer_create(LARGE_PARTICLE_COUNT * 16)

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
    uniforms.append(_large_storage_uniform(9, grain_state_buffer))
    uniforms.append(_large_storage_uniform(10, grain_sleep_buffer))
    uniforms.append(_large_storage_uniform(11, active_count_buffer))
    uniforms.append(_large_storage_uniform(12, wake_impulse_buffer))

    large_uniform_set_rid = rd.uniform_set_create(
        uniforms,
        large_shader_rid,
        0
    )
    if not large_uniform_set_rid.is_valid():
        push_error("Unable to create locked grain uniform set.")
        return

    _initialize_locked_particle_state()
    gpu_ready = true
    _request_surface_readback()
    _request_active_count_readback()

func _initialize_locked_particle_state() -> void:
    var particle_groups := _groups_for(LARGE_PARTICLE_COUNT)
    var surface_groups := _groups_for(SURFACE_COUNT)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, large_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, large_uniform_set_rid, 0)

    _dispatch_locked_phase(compute_list, 6, particle_groups, 0, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_locked_phase(compute_list, 7, surface_groups, 0, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_locked_phase(compute_list, 8, particle_groups, 0, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_locked_phase(compute_list, 11, 1, 0, 0)

    rd.compute_list_end()
    rd.submit()
    rd.sync()

func _run_locked_gpu_step() -> void:
    _upload_large_commands()

    var particle_groups := _groups_for(LARGE_PARTICLE_COUNT)
    var grid_groups := _groups_for(LARGE_GRID_CELL_COUNT)
    var surface_groups := _groups_for(SURFACE_COUNT)
    var command_count := mini(large_commands.size(), LARGE_MAX_COMMANDS)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, large_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, large_uniform_set_rid, 0)

    _dispatch_locked_phase(compute_list, 11, 1, command_count, 0)
    rd.compute_list_add_barrier(compute_list)

    _dispatch_locked_phase(
        compute_list,
        0,
        particle_groups,
        command_count,
        0
    )
    rd.compute_list_add_barrier(compute_list)

    # All grains enter the broadphase so active grains can collide against
    # locked grains. Only active grains perform the expensive contact solve.
    _dispatch_locked_phase(compute_list, 1, grid_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)
    _dispatch_locked_phase(
        compute_list,
        2,
        particle_groups,
        command_count,
        0
    )
    rd.compute_list_add_barrier(compute_list)

    for iteration in range(LOCK_PBD_ITERATIONS):
        _dispatch_locked_phase(
            compute_list,
            3,
            particle_groups,
            command_count,
            iteration
        )
        rd.compute_list_add_barrier(compute_list)
        _dispatch_locked_phase(
            compute_list,
            4,
            particle_groups,
            command_count,
            iteration
        )
        rd.compute_list_add_barrier(compute_list)

    _dispatch_locked_phase(
        compute_list,
        5,
        particle_groups,
        command_count,
        0
    )

    var rebuild_surface := (
        surface_read_counter + 1 >= LOCK_SURFACE_READ_INTERVAL
    )
    if rebuild_surface:
        rd.compute_list_add_barrier(compute_list)
        _dispatch_locked_phase(
            compute_list,
            7,
            surface_groups,
            command_count,
            0
        )
        rd.compute_list_add_barrier(compute_list)
        _dispatch_locked_phase(
            compute_list,
            8,
            particle_groups,
            command_count,
            0
        )

    rd.compute_list_end()
    rd.submit()
    # This only occurs while grains are active. At rest there are no compute
    # submissions or synchronization points at all.
    rd.sync()

    large_commands.clear()

    surface_read_counter += 1
    if rebuild_surface:
        surface_read_counter = 0
        _request_surface_readback()

    active_count_read_counter += 1
    if (
        force_simulation
        or active_count_read_counter >= ACTIVE_COUNT_READ_INTERVAL
    ):
        active_count_read_counter = 0
        _request_active_count_readback()

func _dispatch_locked_phase(
    compute_list: int,
    phase: int,
    groups: int,
    command_count: int,
    iteration: int
) -> void:
    var push := _make_locked_push_constants(
        phase,
        command_count,
        iteration
    )
    rd.compute_list_set_push_constant(compute_list, push, push.size())
    rd.compute_list_dispatch(compute_list, groups, 1, 1)

func _make_locked_push_constants(
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

    push.encode_float(32, LOCK_SIM_DT)
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
    force_simulation = true

func _request_active_count_readback() -> void:
    if (
        rd == null
        or not active_count_buffer.is_valid()
        or active_count_read_pending
    ):
        return

    active_count_read_pending = true
    var error := rd.buffer_get_data_async(
        active_count_buffer,
        _on_active_count_readback
    )
    if error != OK:
        active_count_read_pending = false

func _on_active_count_readback(data: PackedByteArray) -> void:
    active_count_read_pending = false
    if data.size() < 4:
        return

    reported_active_grains = int(data.decode_u32(0))
    if reported_active_grains == 0:
        force_simulation = not large_commands.is_empty()
    else:
        force_simulation = false

func active_grain_count() -> int:
    return reported_active_grains

func active_region_count() -> int:
    return 0

func solver_name() -> String:
    if not gpu_ready:
        return "GPU PBD grain-lock unavailable"
    return "GPU PBD grain-lock / %d active" % reported_active_grains
