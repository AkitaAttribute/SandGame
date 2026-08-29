class_name DebugCameraController
extends Camera3D

const MOVE_SPEED := 5.0
const FAST_MULTIPLIER := 3.0
const MOUSE_SENSITIVITY := 0.0025

var unlocked := false
var locked_transform := Transform3D.IDENTITY
var yaw := 0.0
var pitch := 0.0

func _ready() -> void:
    locked_transform = global_transform
    yaw = rotation.y
    pitch = rotation.x

func set_unlocked(value: bool) -> void:
    unlocked = value
    SkeeBallSettings.debug_camera_unlocked = value

    if not unlocked:
        global_transform = locked_transform
        yaw = rotation.y
        pitch = rotation.x

    if not get_tree().paused:
        Input.mouse_mode = (
            Input.MOUSE_MODE_CAPTURED
            if unlocked
            else Input.MOUSE_MODE_VISIBLE
        )

func _unhandled_input(event: InputEvent) -> void:
    if not unlocked or get_tree().paused:
        return

    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * MOUSE_SENSITIVITY
        pitch = clampf(
            pitch - event.relative.y * MOUSE_SENSITIVITY,
            deg_to_rad(-88.0),
            deg_to_rad(88.0)
        )
        rotation = Vector3(pitch, yaw, 0.0)
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    if not unlocked or get_tree().paused:
        return

    var forward_input := (
        float(Input.is_key_pressed(KEY_W))
        - float(Input.is_key_pressed(KEY_S))
    )
    var right_input := (
        float(Input.is_key_pressed(KEY_D))
        - float(Input.is_key_pressed(KEY_A))
    )
    var vertical_input := (
        float(Input.is_key_pressed(KEY_E))
        - float(Input.is_key_pressed(KEY_Q))
    )

    var move := (
        -global_basis.z * forward_input
        + global_basis.x * right_input
        + Vector3.UP * vertical_input
    )
    if move.length_squared() < 0.0001:
        return

    move = move.normalized()
    var speed := MOVE_SPEED
    if Input.is_key_pressed(KEY_SHIFT):
        speed *= FAST_MULTIPLIER
    global_position += move * speed * delta
