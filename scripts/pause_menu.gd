class_name PauseMenu
extends CanvasLayer

var overlay: ColorRect
var previous_mouse_mode := Input.MOUSE_MODE_CAPTURED

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
    overlay.color = Color(0.0, 0.0, 0.0, 0.58)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.visible = false
    add_child(overlay)

    var label := Label.new()
    label.text = "PAUSED\nEsc to resume"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    label.add_theme_font_size_override("font_size", 34)
    label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
    overlay.add_child(label)
