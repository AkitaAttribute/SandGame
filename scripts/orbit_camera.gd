class_name OrbitCamera
extends Node3D

var target: Node3D
var camera: Camera3D
var yaw := deg_to_rad(35.0)
var elevation := deg_to_rad(58.0)
var distance := 7.5
var mouse_sensitivity := 0.005

func _ready() -> void:
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 58.0
    add_child(camera)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
        return

    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = max(3.5, distance - 0.7)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance = min(13.0, distance + 0.7)
        elif event.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * mouse_sensitivity
        elevation = clamp(elevation + event.relative.y * mouse_sensitivity, deg_to_rad(25.0), deg_to_rad(82.0))

func _process(_delta: float) -> void:
    if target == null or camera == null:
        return

    var focus := target.global_position + Vector3.UP * 0.75
    var horizontal_distance := cos(elevation) * distance
    var offset := Vector3(
        sin(yaw) * horizontal_distance,
        sin(elevation) * distance,
        cos(yaw) * horizontal_distance
    )
    camera.global_position = focus + offset
    camera.look_at(focus, Vector3.UP)
