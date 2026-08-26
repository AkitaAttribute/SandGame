class_name SandFieldV5
extends SandFieldV4

# Rendering/color regions remain 16x16 grains, but simulation cells are 10x10.
# The two grids therefore do not share the same visible boundaries.
const SIM_CHUNK_GRAINS := 10
const SIM_CHUNK_GRID := int(LARGE_AXIS / SIM_CHUNK_GRAINS)
const SIM_CHUNK_COUNT := SIM_CHUNK_GRID * SIM_CHUNK_GRID
const SIM_CHUNK_PARTICLES := SIM_CHUNK_GRAINS * SIM_CHUNK_GRAINS * LARGE_LAYERS
const RENDER_CHUNK_PARTICLES := REGION_GRAINS * REGION_GRAINS * LARGE_LAYERS

var rebuilding_sim_chunk_buffers := false

func _build_chunked_rendering() -> void:
    # There is intentionally no far replacement mesh. Outside the individual
    # grain visibility range, sand simply is not rendered.
    chunk_render_instances.clear()
    chunk_render_materials.clear()
    chunk_far_tiles.clear()

    var render_shader := load("res://shaders/sand_render_chunk.gdshader") as Shader
    if render_shader == null:
        push_error("Unable to load chunked sand render shader.")
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
            chunk_render_materials.append(material)

            var multimesh := MultiMesh.new()
            multimesh.transform_format = MultiMesh.TRANSFORM_3D
            multimesh.mesh = sphere
            multimesh.instance_count = RENDER_CHUNK_PARTICLES
            multimesh.buffer = identity_buffer
            multimesh.custom_aabb = AABB(
                Vector3(center_x - region_half, -1.0, center_z - region_half),
                Vector3(region_half * 2.0, 42.0, region_half * 2.0)
            )

            var instance := MultiMeshInstance3D.new()
            instance.name = "SandRegion_%02d_%02d" % [region_x, region_z]
            instance.multimesh = multimesh
            instance.material_override = material
            instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            instance.visibility_range_end = NEAR_GRAIN_RANGE
            add_child(instance)
            chunk_render_instances.append(instance)

func _initialize_chunked_gpu_solver() -> void:
    # Let V4 create all large particle/grid/texture resources. Suppress its
    # initial 25x25 state read, then replace only the simulation-cell buffers
    # and uniform set with a 40x40 physical partition.
    rebuilding_sim_chunk_buffers = true
    super._initialize_chunked_gpu_solver()

    if rd == null or not gpu_ready:
        rebuilding_sim_chunk_buffers = false
        return

    if large_uniform_set_rid.is_valid():
        rd.free_rid(large_uniform_set_rid)
    if chunk_state_buffer.is_valid():
        rd.free_rid(chunk_state_buffer)
    if chunk_activity_buffer.is_valid():
        rd.free_rid(chunk_activity_buffer)

    var zero_chunks := PackedInt32Array()
    zero_chunks.resize(SIM_CHUNK_COUNT)
    var zero_chunk_bytes := zero_chunks.to_byte_array()
    chunk_state_buffer = rd.storage_buffer_create(
        zero_chunk_bytes.size(),
        zero_chunk_bytes
    )
    chunk_activity_buffer = rd.storage_buffer_create(
        zero_chunk_bytes.size(),
        zero_chunk_bytes
    )

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
    uniforms.append(_large_storage_uniform(9, chunk_state_buffer))
    uniforms.append(_large_storage_uniform(10, chunk_activity_buffer))

    large_uniform_set_rid = rd.uniform_set_create(
        uniforms,
        large_shader_rid,
        0
    )
    if not large_uniform_set_rid.is_valid():
        push_error("Unable to create decoupled sand simulation uniform set.")
        gpu_ready = false
        rebuilding_sim_chunk_buffers = false
        return

    reported_active_regions = 0
    chunk_state_read_counter = 0
    chunk_state_read_pending = false
    force_simulation = false
    rebuilding_sim_chunk_buffers = false
    _request_chunk_state_readback()

func _request_chunk_state_readback() -> void:
    if rebuilding_sim_chunk_buffers:
        return
    super._request_chunk_state_readback()

func _make_large_push_constants(
    phase: int,
    command_count: int,
    iteration: int
) -> PackedByteArray:
    var push := super._make_large_push_constants(
        phase,
        command_count,
        iteration
    )
    # The compute shader's region_size field is the simulation partition size.
    # Rendering continues to use REGION_GRAINS (16) separately.
    push.encode_u32(76, SIM_CHUNK_GRAINS)
    return push

func _run_chunked_gpu_step() -> void:
    _upload_large_commands()

    var particle_groups := _groups_for(LARGE_PARTICLE_COUNT)
    var grid_groups := _groups_for(LARGE_GRID_CELL_COUNT)
    var surface_groups := _groups_for(SURFACE_COUNT)
    var chunk_groups := _groups_for(SIM_CHUNK_COUNT)
    var command_count := mini(large_commands.size(), LARGE_MAX_COMMANDS)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, large_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, large_uniform_set_rid, 0)

    _dispatch_chunked_phase(compute_list, 9, chunk_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)

    _dispatch_chunked_phase(compute_list, 0, particle_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)

    _dispatch_chunked_phase(compute_list, 10, chunk_groups, command_count, 0)
    rd.compute_list_add_barrier(compute_list)

    for iteration in range(CHUNK_PBD_ITERATIONS):
        _dispatch_chunked_phase(compute_list, 1, grid_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_chunked_phase(compute_list, 2, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_chunked_phase(compute_list, 3, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_chunked_phase(compute_list, 4, particle_groups, command_count, iteration)
        rd.compute_list_add_barrier(compute_list)

    _dispatch_chunked_phase(compute_list, 5, particle_groups, command_count, 0)

    var rebuild_surface := (
        surface_read_counter + 1 >= SURFACE_READBACK_INTERVAL
    )
    if rebuild_surface:
        rd.compute_list_add_barrier(compute_list)
        _dispatch_chunked_phase(compute_list, 7, surface_groups, command_count, 0)
        rd.compute_list_add_barrier(compute_list)
        _dispatch_chunked_phase(compute_list, 8, particle_groups, command_count, 0)

    rd.compute_list_end()
    rd.submit()
    rd.sync()

    large_commands.clear()

    surface_read_counter += 1
    if rebuild_surface:
        surface_read_counter = 0
        _request_surface_readback()

    chunk_state_read_counter += 1
    if force_simulation or chunk_state_read_counter >= CHUNK_STATE_READ_INTERVAL:
        chunk_state_read_counter = 0
        _request_chunk_state_readback()

func active_grain_count() -> int:
    return reported_active_regions * SIM_CHUNK_PARTICLES

func active_region_count() -> int:
    return reported_active_regions

func solver_name() -> String:
    if not gpu_ready:
        return "GPU PBD decoupled-chunk unavailable"
    return "GPU PBD / %d active physics cells" % reported_active_regions
