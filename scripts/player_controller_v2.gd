class_name SandPlayerController
extends PlayerController

const FOOT_RADIUS := 0.12
const FOOT_SEPARATION := 0.22
const GROUND_TOLERANCE := 0.065
const SUPPORT_RISE_SPEED := 2.4
const SUPPORT_FALL_SPEED := 0.75
const SUPPORT_RISE_RESPONSE := 14.0
const SUPPORT_FALL_RESPONSE := 5.5

var sand_grounded := false
var smoothed_support_y := 0.0
var support_initialized := false

func _ready() -> void:
    super._ready()
    collision_mask = 1

func _physics_process(delta: float) -> void:
    var input_direction: Vector3 = _camera_relative_input()
    var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
    var desired_velocity: Vector3 = input_direction * WALK_SPEED
    var movement_force: Vector3 = (
        (desired_velocity - horizontal_velocity) * (MASS_KG * RESPONSE)
    )
    velocity += movement_force / MASS_KG * delta

    var support_y := _update_support_height(delta)
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

    if velocity.y <= 0.0 and global_position.y <= support_y + GROUND_TOLERANCE:
        global_position.y = support_y
        velocity.y = 0.0
        sand_grounded = true

    if sand_grounded:
        _couple_planted_foot_to_sand()

func _update_support_height(delta: float) -> float:
    var target := _raw_support_height()
    if not support_initialized:
        smoothed_support_y = target
        support_initialized = true
        return smoothed_support_y

    var rising := target > smoothed_support_y
    var response := SUPPORT_RISE_RESPONSE if rising else SUPPORT_FALL_RESPONSE
    var max_speed := SUPPORT_RISE_SPEED if rising else SUPPORT_FALL_SPEED
    var blend := 1.0 - exp(-response * delta)
    var desired := lerpf(smoothed_support_y, target, blend)
    var max_change := max_speed * delta
    smoothed_support_y = move_toward(smoothed_support_y, desired, max_change)
    return smoothed_support_y

func _raw_support_height() -> float:
    if sand == null:
        return global_position.y

    var right := global_basis.x
    right.y = 0.0
    if right.length_squared() < 0.0001:
        right = Vector3.RIGHT
    else:
        right = right.normalized()

    var forward := -global_basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.0001:
        forward = Vector3.FORWARD
    else:
        forward = forward.normalized()

    var half_gap := FOOT_SEPARATION * 0.5
    var left_point := global_position - right * half_gap
    var right_point := global_position + right * half_gap
    var toe_point := global_position + forward * 0.16
    var heel_point := global_position - forward * 0.12

    var total := 0.0
    total += sand.surface_height_at(left_point)
    total += sand.surface_height_at(right_point)
    total += sand.surface_height_at(toe_point)
    total += sand.surface_height_at(heel_point)
    return total * 0.25

func _couple_planted_foot_to_sand() -> void:
    if sand == null or not (sand is SandFieldV2):
        return

    var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
    if flat_velocity.length_squared() < 0.04:
        return

    var right := global_basis.x
    right.y = 0.0
    if right.length_squared() < 0.0001:
        right = Vector3.RIGHT
    else:
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
        + Vector3.UP * 0.055
    )

    var packed_sand := sand as SandFieldV2
    packed_sand.interact_foot(foot_center, FOOT_RADIUS, flat_velocity)
