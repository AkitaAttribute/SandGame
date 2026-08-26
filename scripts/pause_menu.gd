class_name PauseMenu
extends CanvasLayer

const SETTING_LIMITS := {
    "throw_force": Vector2(0.0, 100.0),
    "explosion_force": Vector2(0.0, 1000.0),
    "blast_radius": Vector2(0.1, 50.0),
    "fuse_duration": Vector2(1.0, 60.0),
}

var overlay: ColorRect
var previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var value_edits: Dictionary = {}

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 100
    _build_overlay()

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
    panel.custom_minimum_size = Vector2(500.0, 0.0)
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
    _add_counter_row(vbox, "blast_radius", "Explosion radius")
    _add_counter_row(vbox, "fuse_duration", "Bomb fuse (seconds)")

    vbox.add_child(HSeparator.new())

    var hint := Label.new()
    hint.text = "Type a value or use - / + (step = 1)"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.add_theme_font_size_override("font_size", 15)
    hint.add_theme_color_override("font_color", Color(0.68, 0.70, 0.75))
    vbox.add_child(hint)

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

    var edit := LineEdit.new()
    edit.custom_minimum_size = Vector2(96.0, 38.0)
    edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    edit.add_theme_font_size_override("font_size", 20)
    edit.select_all_on_focus = true
    edit.text_submitted.connect(_typed_setting_submitted.bind(setting))
    edit.focus_exited.connect(_typed_setting_focus_exited.bind(setting))
    row.add_child(edit)
    value_edits[setting] = edit

    var plus := Button.new()
    plus.text = "+"
    plus.custom_minimum_size = Vector2(48.0, 38.0)
    plus.add_theme_font_size_override("font_size", 20)
    plus.pressed.connect(_change_setting.bind(setting, 1))
    row.add_child(plus)

func _change_setting(setting: String, delta: int) -> void:
    if not SETTING_LIMITS.has(setting):
        return

    # If the user typed a value and then clicked +/- without pressing Enter,
    # commit the typed value first and apply the one-unit step from there.
    _commit_typed_setting(setting)

    var bounds: Vector2 = SETTING_LIMITS[setting]
    var value := clampf(
        _get_setting_value(setting) + float(delta),
        bounds.x,
        bounds.y
    )
    _set_setting_value(setting, value)
    _refresh_setting(setting)

func _typed_setting_submitted(_text: String, setting: String) -> void:
    _commit_typed_setting(setting)
    var edit := value_edits.get(setting) as LineEdit
    if edit != null:
        edit.release_focus()

func _typed_setting_focus_exited(setting: String) -> void:
    _commit_typed_setting(setting)

func _commit_typed_setting(setting: String) -> void:
    if not SETTING_LIMITS.has(setting):
        return

    var edit := value_edits.get(setting) as LineEdit
    if edit == null:
        return

    var text := edit.text.strip_edges()
    if not text.is_valid_float():
        _refresh_setting(setting)
        return

    var bounds: Vector2 = SETTING_LIMITS[setting]
    var value := clampf(float(text), bounds.x, bounds.y)
    _set_setting_value(setting, value)
    _refresh_setting(setting)

func _get_setting_value(setting: String) -> float:
    match setting:
        "throw_force":
            return float(BombOrb.throw_force)
        "explosion_force":
            return float(BombOrb.explosion_force)
        "blast_radius":
            return BombOrb.blast_radius
        "fuse_duration":
            return float(BombOrb.fuse_duration)
    return 0.0

func _set_setting_value(setting: String, value: float) -> void:
    match setting:
        "throw_force":
            BombOrb.throw_force = int(round(value))
        "explosion_force":
            BombOrb.explosion_force = int(round(value))
        "blast_radius":
            BombOrb.blast_radius = value
        "fuse_duration":
            BombOrb.fuse_duration = int(round(value))

func _refresh_values() -> void:
    for setting in value_edits.keys():
        _refresh_setting(String(setting))

func _refresh_setting(setting: String) -> void:
    var edit := value_edits.get(setting) as LineEdit
    if edit == null:
        return

    var value := _get_setting_value(setting)
    if setting == "blast_radius":
        edit.text = str(value)
    else:
        edit.text = str(int(round(value)))
