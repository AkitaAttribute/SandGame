class_name SkeeBallPauseMenu
extends CanvasLayer

const LIMITS := {
    "throw_speed": Vector2(1.0, 60.0),
    "gravity": Vector2(0.0, 30.0),
}

var overlay: ColorRect
var edits: Dictionary = {}
var debug_toggle: CheckButton
var debug_camera: DebugCameraController
var ball: SkeeBallBall

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 100
    _build_overlay()

func configure(camera: DebugCameraController, game_ball: SkeeBallBall) -> void:
    debug_camera = camera
    ball = game_ball
    if debug_toggle != null:
        debug_toggle.button_pressed = SkeeBallSettings.debug_camera_unlocked

func _input(event: InputEvent) -> void:
    if (
        event is InputEventKey
        and event.keycode == KEY_ESCAPE
        and event.pressed
        and not event.echo
    ):
        _set_paused(not get_tree().paused)
        get_viewport().set_input_as_handled()

func _set_paused(paused: bool) -> void:
    if paused:
        get_tree().paused = true
        overlay.visible = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _refresh_values()
        return

    get_tree().paused = false
    overlay.visible = false
    if debug_camera != null:
        debug_camera.set_unlocked(SkeeBallSettings.debug_camera_unlocked)
    else:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_overlay() -> void:
    overlay = ColorRect.new()
    overlay.name = "PauseOverlay"
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.color = Color(0.02, 0.01, 0.01, 0.76)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.visible = false
    add_child(overlay)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(520.0, 0.0)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.13, 0.045, 0.03, 0.98)
    style.border_width_left = 2
    style.border_width_top = 2
    style.border_width_right = 2
    style.border_width_bottom = 2
    style.border_color = Color(0.56, 0.28, 0.09)
    style.corner_radius_top_left = 8
    style.corner_radius_top_right = 8
    style.corner_radius_bottom_left = 8
    style.corner_radius_bottom_right = 8
    style.content_margin_left = 30.0
    style.content_margin_right = 30.0
    style.content_margin_top = 26.0
    style.content_margin_bottom = 26.0
    panel.add_theme_stylebox_override("panel", style)
    center.add_child(panel)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 14)
    panel.add_child(vbox)

    var title := Label.new()
    title.text = "PAUSED"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.62))
    vbox.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Skee-ball prototype tuning"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 17)
    subtitle.add_theme_color_override("font_color", Color(0.83, 0.78, 0.72))
    vbox.add_child(subtitle)
    vbox.add_child(HSeparator.new())

    _add_numeric_row(vbox, "throw_speed", "Ball throw speed")
    _add_numeric_row(vbox, "gravity", "Gravity")

    var debug_row := HBoxContainer.new()
    vbox.add_child(debug_row)
    var debug_label := Label.new()
    debug_label.text = "Unlock debug camera"
    debug_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    debug_label.add_theme_font_size_override("font_size", 18)
    debug_label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
    debug_row.add_child(debug_label)

    debug_toggle = CheckButton.new()
    debug_toggle.button_pressed = SkeeBallSettings.debug_camera_unlocked
    debug_toggle.toggled.connect(_on_debug_camera_toggled)
    debug_row.add_child(debug_toggle)

    var reset_button := Button.new()
    reset_button.text = "Reset ball"
    reset_button.custom_minimum_size = Vector2(0.0, 42.0)
    reset_button.pressed.connect(_reset_ball)
    vbox.add_child(reset_button)

    vbox.add_child(HSeparator.new())

    var debug_hint := Label.new()
    debug_hint.text = "Debug camera: WASD move, Q/E down/up, mouse look, Shift fast"
    debug_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    debug_hint.add_theme_font_size_override("font_size", 14)
    debug_hint.add_theme_color_override("font_color", Color(0.70, 0.68, 0.65))
    vbox.add_child(debug_hint)

    var resume := Label.new()
    resume.text = "Esc to resume"
    resume.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    resume.add_theme_font_size_override("font_size", 17)
    resume.add_theme_color_override("font_color", Color(0.88, 0.84, 0.78))
    vbox.add_child(resume)

    _refresh_values()

func _add_numeric_row(parent: VBoxContainer, setting: String, title: String) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)

    var label := Label.new()
    label.text = title
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size", 18)
    label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
    row.add_child(label)

    var minus := Button.new()
    minus.text = "-"
    minus.custom_minimum_size = Vector2(48.0, 38.0)
    minus.pressed.connect(_step_setting.bind(setting, -1.0))
    row.add_child(minus)

    var edit := LineEdit.new()
    edit.custom_minimum_size = Vector2(110.0, 38.0)
    edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    edit.select_all_on_focus = true
    edit.text_submitted.connect(_submitted.bind(setting))
    edit.focus_exited.connect(_focus_exited.bind(setting))
    row.add_child(edit)
    edits[setting] = edit

    var plus := Button.new()
    plus.text = "+"
    plus.custom_minimum_size = Vector2(48.0, 38.0)
    plus.pressed.connect(_step_setting.bind(setting, 1.0))
    row.add_child(plus)

func _step_setting(setting: String, delta: float) -> void:
    _commit(setting)
    var bounds: Vector2 = LIMITS[setting]
    _set_value(setting, clampf(_get_value(setting) + delta, bounds.x, bounds.y))
    _refresh(setting)

func _submitted(_text: String, setting: String) -> void:
    _commit(setting)
    var edit := edits.get(setting) as LineEdit
    if edit != null:
        edit.release_focus()

func _focus_exited(setting: String) -> void:
    _commit(setting)

func _commit(setting: String) -> void:
    if not LIMITS.has(setting):
        return
    var edit := edits.get(setting) as LineEdit
    if edit == null:
        return
    var text := edit.text.strip_edges()
    if not text.is_valid_float():
        _refresh(setting)
        return
    var bounds: Vector2 = LIMITS[setting]
    _set_value(setting, clampf(float(text), bounds.x, bounds.y))
    _refresh(setting)

func _get_value(setting: String) -> float:
    match setting:
        "throw_speed":
            return SkeeBallSettings.throw_speed
        "gravity":
            return SkeeBallSettings.gravity
    return 0.0

func _set_value(setting: String, value: float) -> void:
    match setting:
        "throw_speed":
            SkeeBallSettings.throw_speed = value
        "gravity":
            SkeeBallSettings.gravity = value

func _refresh_values() -> void:
    for setting in edits.keys():
        _refresh(String(setting))

func _refresh(setting: String) -> void:
    var edit := edits.get(setting) as LineEdit
    if edit != null:
        edit.text = str(snappedf(_get_value(setting), 0.01))

func _on_debug_camera_toggled(enabled: bool) -> void:
    SkeeBallSettings.debug_camera_unlocked = enabled
    if debug_camera != null:
        debug_camera.set_unlocked(enabled)

func _reset_ball() -> void:
    if ball != null:
        ball.reset_to_start()
