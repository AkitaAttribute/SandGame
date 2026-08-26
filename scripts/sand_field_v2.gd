class_name SandFieldV2
extends SandField

const PACKED_REACTION_SCALE := 3.6
const BODY_CONTACT_FRICTION := 0.82
const BODY_CONTACT_BIAS := 52.0
const MAX_PACKED_REACTION_IMPULSE := 2.25
const SURFACE_SAMPLE_RADIUS := 0.48
const SURFACE_TOP_BAND := GRAIN_RADIUS * 0.80
const PACKED_GRAIN_FRICTION := 0.72

func _make_push_constants(
    phase: int,
    command_count: int,
    iteration: int
) -> PackedByteArray:
    var push := super._make_push_constants(phase, command_count, iteration)
    push.encode_float(52, PACKED_GRAIN_FRICTION)
    return push

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
        var relative_velocity := body_velocity - grain_velocity
        var closing_speed := maxf(0.0, relative_velocity.dot(normal))
        var bias_speed := penetration * BODY_CONTACT_BIAS

        var normal_impulse := reduced_mass * (
            closing_speed * (1.0 + RESTITUTION) + bias_speed
        ) * PACKED_REACTION_SCALE
        reaction_impulse -= normal * normal_impulse

        var tangent := relative_velocity - normal * relative_velocity.dot(normal)
        var tangent_speed := tangent.length()
        if tangent_speed > 0.0001 and normal_impulse > 0.0:
            var friction_impulse := minf(
                reduced_mass * tangent_speed,
                normal_impulse * BODY_CONTACT_FRICTION
            )
            reaction_impulse -= tangent / tangent_speed * friction_impulse

    if reaction_impulse.length() > MAX_PACKED_REACTION_IMPULSE:
        reaction_impulse = (
            reaction_impulse.normalized() * MAX_PACKED_REACTION_IMPULSE
        )

    return reaction_impulse

func interact_foot(
    center: Vector3,
    radius: float,
    travel_velocity: Vector3
) -> void:
    var flat_velocity := Vector3(travel_velocity.x, 0.0, travel_velocity.z)
    _queue_command(center, radius, flat_velocity, 3.0)

func surface_height_at(world_position: Vector3) -> float:
    if cpu_positions.is_empty():
        return PLAYER_SURFACE_Y

    var radius_squared := SURFACE_SAMPLE_RADIUS * SURFACE_SAMPLE_RADIUS
    var candidate_heights: Array[float] = []
    var highest := -INF

    for i in range(PARTICLE_COUNT):
        var p := cpu_positions[i]
        var dx := p.x - world_position.x
        var dz := p.z - world_position.z
        var horizontal_squared := dx * dx + dz * dz
        if horizontal_squared > radius_squared:
            continue

        var grain_velocity := (
            (cpu_positions[i] - cpu_previous_positions[i]) / SIM_DT
        )
        if grain_velocity.length_squared() > 2.25:
            continue

        if p.y > world_position.y + 0.45:
            continue

        var top := p.y + GRAIN_RADIUS
        candidate_heights.append(top)
        highest = maxf(highest, top)

    if candidate_heights.is_empty():
        return GRAIN_RADIUS

    var total := 0.0
    var count := 0
    var minimum_top := highest - SURFACE_TOP_BAND
    for height in candidate_heights:
        if height >= minimum_top:
            total += height
            count += 1

    if count == 0:
        return highest
    return total / float(count)

func solver_name() -> String:
    return "GPU PBD smoothed-contact" if gpu_ready else "GPU PBD unavailable"
