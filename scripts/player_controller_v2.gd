class_name SandPlayerController
extends PlayerController

const FOOT_RADIUS := 0.12
const FOOT_SEPARATION := 0.22
const GROUND_TOLERANCE := 0.055

var sand_grounded := false

func _ready() -> void:
    super._ready()
    # There is no artificial floor at the top of the sand anymore. Layer 1 is
    # only the real y=0 world floor and rigid-body projectiles.
    collision_mask = 1

func _physics_process(delta: float) -> void:
    var input_direction: Vector3 = _camera_relative_input()
    var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
    var desired_velocity: Vector3 = input_direction * WALK_SPEED
    var movement_force: Vector3 = (
        (desired_velocity - horizontal_velocity) * (MASS_KG * RESPONSE)
    )
    velocity += movement_force / MASS_KG * delta

    var support_y := _support_height()
    sand_grounded = (
        global_position.y <= support_y + GROUND_TOLERANCE
        and velocity.y <= 0.35
    )

    if sand_grounded:
        if global_position.y < support_y:
            global_position.y = support_y
        if velocity.y < 0.0:
            velocity.y = 0.0

        if Input.is_key_pressed(KEY_SPACE):
            apply_impulse(Vector3.UP * JUMP_IMPULSE)
            sand_grounded = false
    else:
        velocity.y -= GRAVITY * delta

    if input_direction.length_squared() > 0.01:
        rotation.y = lerp_angle(
            rotation.y,
            atan2(-input_direction.x, -input_direction.z),
            minf(1.0, delta * 11.0)
        )
        _play_walk()
    else:
        velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * delta * 4.0)
        velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * delta * 4.0)
        _play_idle_if_possible()

    move_and_slide()

    if sand != null:
        global_position = sand.clamp_inside(global_position)

    # Resolve the player's feet against the actual current grain surface.
    # This is a PBD-style positional floor constraint derived from particles,
    # not a hidden collision slab.
    if velocity.y <= 0.0:
        var landing_y := _support_height()
        if global_position.y <= landing_y + GROUND_TOLERANCE:
            global_position.y = landing_y
            velocity.y = 0.0
            sand_grounded = true

    if sand_grounded:
        _couple_planted_foot_to_sand(delta)

func _support_height() -> float:
    if sand == null:
        return global_position.y

    var right := global_basis.x
    right.y = 0.0
    if right.length_squared() < 0.0001:
        right = Vector3.RIGHT
    else:
        right = right.normalized()

    var half_gap := FOOT_SEPARATION * 0.5
    var left_point := global_position - right * half_gap
    var right_point := global_position + right * half_gap

    var left_height := sand.surface_height_at(left_point)
    var right_height := sand.surface_height_at(right_point)
    return (left_height + right_height) * 0.5

func _couple_planted_foot_to_sand(delta: float) -> void:
    if sand == null:
        return

    var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
    if flat_velocity.length_squared() < 0.04:
        return

    var right := global_basis.x
    right.y = 0.0
    right = right.normalized()

    var planted_side := 1.0
    if animation_player != null and walk_animation != "":
        var length := animation_player.current_animation_length
        if length > 0.001:
            var phase := fmod(
                animation_player.current_animation_position / length,
                1.0
            )
            planted_side = -1.0 if phase < 0.5 else 1.0

    var foot_center := (
        global_position
        + right * planted_side * FOOT_SEPARATION * 0.5
        + Vector3.UP * 0.085
    )

    # The planted foot is an external PBD collider. Its motion displaces the
    # exact grains it intersects; nothing is painted or regenerated afterward.
    sand.interact_sphere(
        foot_center,
        FOOT_RADIUS,
        velocity,
        MASS_KG * 0.5,
        delta
    )
