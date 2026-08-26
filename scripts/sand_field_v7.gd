class_name SandFieldV7
extends SandFieldV6

# Adds a per-grain movement lifetime safety net without ever freezing airborne
# grains. Expired grains enter a non-propagating settling state and continue
# under gravity/collision until their actual displacement becomes negligible.
var settle_shader_rid := RID()
var settle_pipeline_rid := RID()
var settle_uniform_set_rid := RID()

func _ready() -> void:
    super._ready()
    if gpu_ready:
        _initialize_settle_pipeline()

func _exit_tree() -> void:
    if rd != null:
        for rid in [
            settle_uniform_set_rid,
            settle_pipeline_rid,
            settle_shader_rid,
        ]:
            if rid.is_valid():
                rd.free_rid(rid)
    super._exit_tree()

func _initialize_settle_pipeline() -> void:
    var shader_file := load(
        "res://shaders/sand_settle_lifetime.glsl"
    ) as RDShaderFile
    if shader_file == null:
        push_error("Unable to load sand settle lifetime shader.")
        return

    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    settle_shader_rid = rd.shader_create_from_spirv(spirv)
    if not settle_shader_rid.is_valid():
        push_error("Unable to create sand settle lifetime shader.")
        return

    settle_pipeline_rid = rd.compute_pipeline_create(settle_shader_rid)
    if not settle_pipeline_rid.is_valid():
        push_error("Unable to create sand settle lifetime pipeline.")
        return

    var uniforms: Array[RDUniform] = []
    uniforms.append(_large_storage_uniform(0, large_position_buffer))
    uniforms.append(_large_storage_uniform(1, large_previous_position_buffer))
    uniforms.append(_large_storage_uniform(2, large_velocity_buffer))
    uniforms.append(_large_storage_uniform(9, grain_state_buffer))
    uniforms.append(_large_storage_uniform(12, wake_impulse_buffer))

    settle_uniform_set_rid = rd.uniform_set_create(
        uniforms,
        settle_shader_rid,
        0
    )
    if not settle_uniform_set_rid.is_valid():
        push_error("Unable to create sand settle lifetime uniform set.")

func _run_locked_gpu_step() -> void:
    super._run_locked_gpu_step()

    if (
        rd == null
        or not settle_pipeline_rid.is_valid()
        or not settle_uniform_set_rid.is_valid()
    ):
        return

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(
        compute_list,
        settle_pipeline_rid
    )
    rd.compute_list_bind_uniform_set(
        compute_list,
        settle_uniform_set_rid,
        0
    )
    rd.compute_list_dispatch(
        compute_list,
        _groups_for(LARGE_PARTICLE_COUNT),
        1,
        1
    )
    rd.compute_list_end()

    # No second CPU/GPU sync is needed. This pass only updates per-grain
    # activity/velocity state, and the next simulation submission is ordered
    # behind it on the same RenderingDevice queue.
    rd.submit()

func solver_name() -> String:
    if not gpu_ready:
        return "GPU PBD grain-lock unavailable"
    return "GPU PBD grain-lock + settling / %d active" % reported_active_grains
