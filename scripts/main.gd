extends Node3D

var sand: SandField
var player: PlayerController
var orbit_camera: OrbitCamera

func _ready() -> void:
    _build_lighting()

    sand = SandField.new()
    sand.name = "SandField"
    add_child(sand)

    player = PlayerController.new()
    player.name = "Player"
    add_child(player)
    player.sand = sand
    player.global_position = Vector3(0.0, sand.surface_height_at(Vector3.ZERO) + 1.0, 0.0)

    orbit_camera = OrbitCamera.new()
    orbit_camera.name = "OrbitCamera"
    add_child(orbit_camera)
    orbit_camera.target = player
    player.aim_camera = orbit_camera.camera

    _build_ui()

func _build_lighting() -> void:
    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.48, 0.72, 0.9)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.72, 0.76, 0.82)
    environment.ambient_light_energy = 0.65
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment_node.environment = environment
    add_child(environment_node)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    add_child(sun)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    var label := Label.new()
    label.position = Vector2(18.0, 16.0)
    label.text = "WASD move   Space jump   Left click throw   Mouse orbit   Wheel zoom\n0.7 g   Player mass: 20 lb / 9.07 kg   Orb fuse: 3 s"
    label.add_theme_font_size_override("font_size", 17)
    label.add_theme_color_override("font_color", Color(0.06, 0.06, 0.07))
    layer.add_child(label)
