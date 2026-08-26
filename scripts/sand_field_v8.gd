class_name SandFieldV8
extends SandFieldV6

# Global render path for the per-grain locked solver.
# Rendering no longer has region/chunk ownership: all 800k grains live in one
# MultiMesh and INSTANCE_ID maps directly to the persistent particle ID.
func _build_full_grain_rendering() -> void:
    full_render_instances.clear()
    full_render_materials.clear()

    var render_shader := load("res://shaders/sand_render_global.gdshader") as Shader
    if render_shader == null:
        push_error("Unable to load global sand render shader.")
        return

    var sphere := SphereMesh.new()
    sphere.radius = GRAIN_RADIUS
    sphere.height = GRAIN_DIAMETER
    sphere.radial_segments = 4
    sphere.rings = 2

    var identity_buffer := PackedFloat32Array()
    identity_buffer.resize(LARGE_PARTICLE_COUNT * 12)
    for i in range(LARGE_PARTICLE_COUNT):
        var base := i * 12
        identity_buffer[base + 0] = 1.0
        identity_buffer[base + 5] = 1.0
        identity_buffer[base + 10] = 1.0

    var material := ShaderMaterial.new()
    material.shader = render_shader
    material.set_shader_parameter(
        "position_texture_width",
        POSITION_TEXTURE_WIDTH
    )
    material.set_shader_parameter("axis_particles", LARGE_AXIS)
    material.set_shader_parameter("region_size", REGION_GRAINS)
    full_render_materials.append(material)

    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = sphere
    multimesh.instance_count = LARGE_PARTICLE_COUNT
    multimesh.buffer = identity_buffer

    # There is deliberately one global culling bound. Particle simulation and
    # color regions have no render ownership, so moved grains cannot disappear
    # because an unrelated source region left the camera frustum.
    multimesh.custom_aabb = AABB(
        Vector3(
            -LARGE_BOUNDARY_HALF_EXTENT,
            -2.0,
            -LARGE_BOUNDARY_HALF_EXTENT
        ),
        Vector3(
            LARGE_BOUNDARY_HALF_EXTENT * 2.0,
            512.0,
            LARGE_BOUNDARY_HALF_EXTENT * 2.0
        )
    )

    var instance := MultiMeshInstance3D.new()
    instance.name = "SandRender_Global"
    instance.multimesh = multimesh
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(instance)
    full_render_instances.append(instance)
