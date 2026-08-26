class_name PauseMenu
extends CanvasLayer

const SETTING_LIMITS := {
    "throw_force": Vector2i(0, 100),
    "explosion_force": Vector2i(0, 500),
    "fuse_duration": Vector2i(1, 60),
}

var overlay: ColorRect
var previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var value_labels: Dictionary = {}

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 100
    _build_overlay()

func _unhandled_input(event: InputEvent) -> void:
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
        previous_mouse_mode = Input.mouse_mode
        get_tree().paused = true
        overlay.visible = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _refresh_values()
        return

    get_tree().paused = false
    overlay.visible = false
    if previous_mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_overlay() -> void:
    overlay = ColorRect.new()
    overlay.name = "PauseOverlay"
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.color = Color(0.0, 0.0, 0.0, 0.62)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.visible = false
    add_child(overlay)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(460.0, 0.0)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
    panel_style.border_width_left = 1
    panel_style.border_width_top = 1
    panel_style.border_width_right = 1
    panel_style.border_width_bottom = 1
    panel_style.border_color = Color(0.34, 0.36, 0.42, 1.0)
    panel_style.corner_radius_top_left = 8
    panel_style.corner_radius_top_right = 8
    panel_style.corner_radius_bottom_left = 8
    panel_style.corner_radius_bottom_right = 8
    panel_style.content_margin_left = 28.0
    panel_style.content_margin_right = 28.0
    panel_style.content_margin_top = 24.0
    panel_style.content_margin_bottom = 24.0
    panel.add_theme_stylebox_override("panel", panel_style)
    center.add_child(panel)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 14)
    panel.add_child(vbox)

    var title := Label.new()
    title.text = "PAUSED"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
    vbox.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Bomb tuning"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 18)
    subtitle.add_theme_color_override("font_color", Color(0.75, 0.77, 0.82))
    vbox.add_child(subtitle)

    vbox.add_child(HSeparator.new())

    _add_counter_row(vbox, "throw_force", "Throw force")
    _add_counter_row(vbox, "explosion_force", "Explosion force")
    _add_counter_row(vbox, "fuse_duration", "Bomb fuse (seconds)")

    vbox.add_child(HSeparator.new())

    var resume := Label.new()
    resume.text = "Esc to resume"
    resume.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    resume.add_theme_font_size_override("font_size", 17)
    resume.add_theme_color_override("font_color", Color(0.82, 0.83, 0.87))
    vbox.add_child(resume)

    _refresh_values()

func _add_counter_row(parent: VBoxContainer, setting: String, title: String) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)

    var name_label := Label.new()
    name_label.text = title
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_label.add_theme_font_size_override("font_size", 18)
    name_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
    row.add_child(name_label)

    var minus := Button.new()
    minus.text = "-"
    minus.custom_minimum_size = Vector2(48.0, 38.0)
    minus.add_theme_font_size_override("font_size", 20)
    minus.pressed.connect(_change_setting.bind(setting, -1))
    row.add_child(minus)

    var value_label := Label.new()
    value_label.custom_minimum_size = Vector2(72.0, 38.0)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    value_label.add_theme_font_size_override("font_size", 20)
    value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
    row.add_child(value_label)
    value_labels[setting] = value_label

    var plus := Button.new()
    plus.text = "+"
    plus.custom_minimum_size = Vector2(48.0, 38.0)
    plus.add_theme_font_size_override("font_size", 20)
    plus.pressed.connect(_change_setting.bind(setting, 1))
    row.add_child(plus)

func _change_setting(setting: String, delta: int) -> void:
    if not SETTING_LIMITS.has(setting):
        return

    var bounds: Vector2i = SETTING_LIMITS[setting]
    var value := clampi(
        _get_setting_value(setting) + delta,
        bounds.x,
        bounds.y
    )
    _set_setting_value(setting, value)
    _refresh_setting(setting)

func _get_setting_value(setting: String) -> int:
    match setting:
        "throw_force":
            return BombOrb.throw_force
        "explosion_force":
            return BombOrb.explosion_force
        "fuse_duration":
            return BombOrb.fuse_duration
    return 0

func _set_setting_value(setting: String, value: int) -> void:
    match setting:
        "throw_force":
            BombOrb.throw_force = value
        "explosion_force":
            BombOrb.explosion_force = value
        "fuse_duration":
            BombOrb.fuse_duration = value

func _refresh_values() -> void:
    for setting in value_labels.keys():
        _refresh_setting(String(setting))

func _refresh_setting(setting: String) -> void:
    var label := value_labels.get(setting) as Label
    if label != null:
        label.text = str(_get_setting_value(setting))
