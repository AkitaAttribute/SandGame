extends Node3D

var sand: SandField
var player: PlayerController
var orbit_camera: OrbitCamera
var status_label: Label
var status_refresh := 0.0

func _ready() -> void:
    _build_lighting()

    sand = SandFieldV2.new()
    sand.name = "SandField"
    add_child(sand)

    _build_physical_floor(sand.world_size())

    player = SandPlayerController.new()
    player.name = "Player"
    add_child(player)
    player.sand = sand
    player.global_position = Vector3(
        0.0,
        sand.surface_height_at(Vector3.ZERO) + 0.03,
        0.0
    )

    orbit_camera = OrbitCamera.new()
    orbit_camera.name = "OrbitCamera"
    add_child(orbit_camera)
    orbit_camera.target = player
    player.aim_camera = orbit_camera.camera

    _build_ui()

func _process(delta: float) -> void:
    status_refresh += delta
    if status_label == null or status_refresh < 0.20:
        return

    status_refresh = 0.0
    status_label.text = (
        "WASD move   Space jump   Left click throw   Mouse orbit   Wheel zoom\n"
        + "0.7 g   Player mass: 20 lb / 9.07 kg   Orb fuse: 3 s   "
        + "Sand grains: %d   Solver: %s"
        % [sand.grain_count(), sand.solver_name()]
    )

func _build_physical_floor(world_size: float) -> void:
    var floor_body := StaticBody3D.new()
    floor_body.name = "WorldFloor"
    floor_body.collision_layer = 1
    floor_body.collision_mask = 1
    add_child(floor_body)

    # This is the actual bottom of the simulation volume at y=0. There is no
    # second player support surface hidden at the top of the sand.
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(world_size, 0.02, world_size)
    collision.shape = shape
    collision.position.y = -0.01
    floor_body.add_child(collision)

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

    status_label = Label.new()
    status_label.position = Vector2(18.0, 16.0)
    status_label.add_theme_font_size_override("font_size", 17)
    status_label.add_theme_color_override("font_color", Color(0.06, 0.06, 0.07))
    layer.add_child(status_label)

    status_refresh = 1.0
