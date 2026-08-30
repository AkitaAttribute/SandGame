extends Node3D

var machine: SkeeBallMachine
var ball: SkeeBallBall
var debug_camera: DebugCameraController
var pause_menu: SkeeBallPauseMenu

var score_label: Label
var help_label: Label
var swipe_line: Line2D

var score := 0
var rolls := 0
var gesture_active := false
var gesture_start := Vector2.ZERO
var gesture_current := Vector2.ZERO
var active_touch_id := -1
var touches_down: Dictionary = {}

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    _build_room()
    _build_lighting()

    machine = SkeeBallMachine.new()
    machine.name = "SkeeBallMachine"
    add_child(machine)
    machine.scored.connect(_on_machine_scored)

    ball = SkeeBallBall.new()
    ball.name = "GameBall"
    add_child(ball)
    ball.configure_start(machine.ball_start_transform())

    debug_camera = DebugCameraController.new()
    debug_camera.name = "GameCamera"
    debug_camera.current = true
    add_child(debug_camera)
    debug_camera.global_position = Vector3(0.0, 4.20, 10.40)
    debug_camera.look_at(Vector3(0.0, 2.70, -1.00), Vector3.UP)
    debug_camera.locked_transform = debug_camera.global_transform
    debug_camera.yaw = debug_camera.rotation.y
    debug_camera.pitch = debug_camera.rotation.x

    _build_ui()

    pause_menu = SkeeBallPauseMenu.new()
    pause_menu.name = "PauseMenu"
    add_child(pause_menu)
    pause_menu.configure(debug_camera, ball)

func _input(event: InputEvent) -> void:
    if get_tree().paused or SkeeBallSettings.debug_camera_unlocked:
        return

    if event is InputEventMouseButton:
        var mouse_button := event as InputEventMouseButton
        if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
            _cancel_gesture_and_reset()
            get_viewport().set_input_as_handled()
            return

        if mouse_button.button_index == MOUSE_BUTTON_LEFT:
            if mouse_button.pressed:
                _begin_gesture(mouse_button.position, -1)
            elif gesture_active and active_touch_id == -1:
                gesture_current = mouse_button.position
                _finish_gesture()
            get_viewport().set_input_as_handled()
            return

    if event is InputEventMouseMotion:
        if gesture_active and active_touch_id == -1:
            gesture_current = (event as InputEventMouseMotion).position
            _update_swipe_line()
        return

    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            if not touches_down.is_empty():
                touches_down[touch.index] = true
                _cancel_gesture_and_reset()
                get_viewport().set_input_as_handled()
                return

            touches_down[touch.index] = true
            _begin_gesture(touch.position, touch.index)
        else:
            touches_down.erase(touch.index)
            if gesture_active and touch.index == active_touch_id:
                gesture_current = touch.position
                _finish_gesture()
        get_viewport().set_input_as_handled()
        return

    if event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if gesture_active and drag.index == active_touch_id:
            gesture_current = drag.position
            _update_swipe_line()
            get_viewport().set_input_as_handled()

func _begin_gesture(position: Vector2, pointer_id: int) -> void:
    if ball == null or not ball.is_waiting():
        return

    var viewport_size := get_viewport().get_visible_rect().size
    if position.y < viewport_size.y * 0.58:
        return

    gesture_active = true
    gesture_start = position
    gesture_current = position
    active_touch_id = pointer_id
    swipe_line.visible = true
    _update_swipe_line()

func _finish_gesture() -> void:
    if not gesture_active:
        return

    var viewport_size := get_viewport().get_visible_rect().size
    var swipe := gesture_current - gesture_start
    var upward_distance := -swipe.y

    gesture_active = false
    active_touch_id = -1
    swipe_line.visible = false

    if upward_distance < 24.0:
        ball.reset_to_start()
        return

    var power := clampf(
        upward_distance / maxf(1.0, viewport_size.y * 0.30),
        0.10,
        1.50
    )
    var horizontal := clampf(
        swipe.x / maxf(1.0, viewport_size.x * 0.28),
        -0.55,
        0.55
    )
    var direction := Vector3(horizontal, 0.0, -1.0).normalized()
    var speed := SkeeBallSettings.throw_speed * power

    rolls += 1
    ball.launch(direction, speed)
    _refresh_score()

func _cancel_gesture_and_reset() -> void:
    gesture_active = false
    active_touch_id = -1
    if swipe_line != null:
        swipe_line.visible = false
    if ball != null:
        ball.reset_to_start()

func _update_swipe_line() -> void:
    if swipe_line == null:
        return
    swipe_line.points = PackedVector2Array([gesture_start, gesture_current])

func _on_machine_scored(points: int, scored_ball: SkeeBallBall) -> void:
    score += points
    _refresh_score("+%d" % points)

    # The score trigger now sits directly at the mouth of each through-hole.
    # Hold only briefly so the scored opening is perceptible, then reset.
    await get_tree().create_timer(0.18).timeout
    if is_instance_valid(scored_ball) and scored_ball.scored:
        scored_ball.reset_to_start()
        _refresh_score()

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 10
    add_child(layer)

    score_label = Label.new()
    score_label.position = Vector2(18.0, 14.0)
    score_label.add_theme_font_size_override("font_size", 24)
    score_label.add_theme_color_override("font_color", Color(0.96, 0.89, 0.70))
    score_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.03, 0.02, 0.9))
    score_label.add_theme_constant_override("shadow_offset_x", 2)
    score_label.add_theme_constant_override("shadow_offset_y", 2)
    score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(score_label)

    help_label = Label.new()
    help_label.text = "Drag upward from the bottom to roll   •   Right-click / second touch resets   •   Esc menu"
    help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    help_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    help_label.position.y = -42.0
    help_label.add_theme_font_size_override("font_size", 16)
    help_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
    help_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.01, 0.95))
    help_label.add_theme_constant_override("shadow_offset_x", 2)
    help_label.add_theme_constant_override("shadow_offset_y", 2)
    help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(help_label)

    swipe_line = Line2D.new()
    swipe_line.width = 7.0
    swipe_line.default_color = Color(1.0, 0.78, 0.24, 0.82)
    swipe_line.antialiased = true
    swipe_line.visible = false
    layer.add_child(swipe_line)

    _refresh_score()

func _refresh_score(extra: String = "") -> void:
    if score_label == null:
        return
    score_label.text = "SCORE  %d    ROLLS  %d" % [score, rolls]
    if extra != "":
        score_label.text += "    %s" % extra

func _build_lighting() -> void:
    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.055, 0.018, 0.012)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.82, 0.64, 0.50)
    environment.ambient_light_energy = 0.48
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_environment.environment = environment
    add_child(world_environment)

    _add_room_light(Vector3(0.0, 9.7, 8.0), 5.0, 20.0, true)
    _add_room_light(Vector3(0.0, 9.2, 0.0), 4.5, 18.0, false)
    _add_room_light(Vector3(0.0, 8.6, -7.0), 5.0, 17.0, false)

func _add_room_light(position: Vector3, energy: float, range: float, shadows: bool) -> void:
    var light := OmniLight3D.new()
    light.position = position
    light.light_color = Color(1.0, 0.84, 0.67)
    light.light_energy = energy
    light.omni_range = range
    light.shadow_enabled = shadows
    add_child(light)

func _build_room() -> void:
    var mahogany := StandardMaterial3D.new()
    mahogany.albedo_color = Color(0.26, 0.055, 0.035)
    mahogany.roughness = 0.80

    var mahogany_floor := StandardMaterial3D.new()
    mahogany_floor.albedo_color = Color(0.20, 0.040, 0.026)
    mahogany_floor.roughness = 0.86

    _add_room_box("Floor", Vector3(18.0, 0.30, 32.0), Vector3(0.0, -0.15, 1.0), mahogany_floor)
    _add_room_box("Ceiling", Vector3(18.0, 0.25, 32.0), Vector3(0.0, 11.75, 1.0), mahogany)
    _add_room_box("LeftWall", Vector3(0.28, 12.0, 32.0), Vector3(-9.0, 5.85, 1.0), mahogany)
    _add_room_box("RightWall", Vector3(0.28, 12.0, 32.0), Vector3(9.0, 5.85, 1.0), mahogany)
    _add_room_box("BackWall", Vector3(18.0, 12.0, 0.28), Vector3(0.0, 5.85, -15.0), mahogany)
    _add_room_box("FrontWall", Vector3(18.0, 12.0, 0.28), Vector3(0.0, 5.85, 17.0), mahogany)

func _add_room_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    material: Material
) -> void:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = position
    body.collision_layer = 1
    body.collision_mask = 1
    add_child(body)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    mesh_instance.mesh = mesh
    body.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
