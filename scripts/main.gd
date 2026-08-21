extends Node3D

const WORLD_FLOOR_SIZE := 12.0

var sand: SandField
var player: PlayerController
var orbit_camera: OrbitCamera

func _ready() -> void:
    _build_lighting()
    _build_physical_floor()

    sand = SandField.new()
    sand.name = "SandField"
    add_child(sand)

    _build_player_support(sand.surface_height_at(Vector3.ZERO))

    player = PlayerController.new()
    player.name = "Player"
    add_child(player)
    player.sand = sand
    player.global_position = Vector3(0.0, sand.surface_height_at(Vector3.ZERO) + 0.03, 0.0)

    orbit_camera = OrbitCamera.new()
    orbit_camera.name = "OrbitCamera"
    add_child(orbit_camera)
    orbit_camera.target = player
    player.aim_camera = orbit_camera.camera

    _build_ui()

func _build_physical_floor() -> void:
    var floor_body := StaticBody3D.new()
    floor_body.name = "BombAndSandFloor"
    floor_body.collision_layer = 1
    floor_body.collision_mask = 1
    add_child(floor_body)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(WORLD_FLOOR_SIZE, 0.10, WORLD_FLOOR_SIZE)
    collision.shape = shape
    collision.position.y = -0.05
    floor_body.add_child(collision)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(WORLD_FLOOR_SIZE, 0.10, WORLD_FLOOR_SIZE)

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.20, 0.17, 0.14)
    material.roughness = 1.0
    mesh.material = material

    mesh_instance.mesh = mesh
    mesh_instance.position.y = -0.05
    add_child(mesh_instance)

func _build_player_support(surface_y: float) -> void:
    var support_body := StaticBody3D.new()
    support_body.name = "TemporaryPlayerSupport"
    support_body.collision_layer = 2
    support_body.collision_mask = 2
    add_child(support_body)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(WORLD_FLOOR_SIZE, 0.05, WORLD_FLOOR_SIZE)
    collision.shape = shape
    collision.position.y = surface_y - 0.025
    support_body.add_child(collision)

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
    label.text = (
        "WASD move   Space jump   Left click throw   Mouse orbit   Wheel zoom\n"
        + "0.7 g   Player mass: 20 lb / 9.07 kg   Orb fuse: 3 s   "
        + "Sand grains: %d fixed pool" % sand.grain_count()
    )
    label.add_theme_font_size_override("font_size", 17)
    label.add_theme_color_override("font_color", Color(0.06, 0.06, 0.07))
    layer.add_child(label)
