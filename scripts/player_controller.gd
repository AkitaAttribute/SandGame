class_name PlayerController
extends CharacterBody3D

const MASS_KG := 9.07185
const GRAVITY := 6.867
const CHARACTER_HEIGHT := 1.55
const WALK_SPEED := 3.4
const RESPONSE := 8.5
const JUMP_IMPULSE := MASS_KG * sqrt(2.0 * GRAVITY * CHARACTER_HEIGHT)
const MODEL_PATH := "res://addons/kaykit_character_pack_skeletons/Characters/gltf/Skeleton_Warrior.glb"

var sand: SandField
var aim_camera: Camera3D
var visual_root: Node3D
var animation_player: AnimationPlayer
var idle_animation := ""
var walk_animation := ""
var throw_animation := ""
var throw_locked := false

func _ready() -> void:
    add_to_group("player")
    collision_layer = 2
    collision_mask = 2
    floor_max_angle = deg_to_rad(50.0)
    floor_snap_length = 0.22

    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.26
    capsule.height = CHARACTER_HEIGHT
    collision.shape = capsule
    collision.position.y = CHARACTER_HEIGHT * 0.50
    add_child(collision)

    _load_visual()

func _load_visual() -> void:
    visual_root = Node3D.new()
    visual_root.name = "Visual"
    add_child(visual_root)

    if ResourceLoader.exists(MODEL_PATH):
        var scene := load(MODEL_PATH) as PackedScene
        if scene != null:
            var model := scene.instantiate()
            model.name = "KayKitSkeletonWarrior"
            model.rotation.y = PI
            model.scale = Vector3.ONE * 0.86
            visual_root.add_child(model)
            animation_player = _find_animation_player(model)
            _discover_animations()
            return

    _build_fallback_visual()

func _build_fallback_visual() -> void:
    var body := MeshInstance3D.new()
    var capsule_mesh := CapsuleMesh.new()
    capsule_mesh.radius = 0.24
    capsule_mesh.height = 1.05
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.82, 0.82, 0.78)
    capsule_mesh.material = material
    body.mesh = capsule_mesh
    body.position.y = 0.78
    visual_root.add_child(body)

    var head := MeshInstance3D.new()
    var head_mesh := SphereMesh.new()
    head_mesh.radius = 0.24
    head_mesh.height = 0.48
    head_mesh.material = material
    head.mesh = head_mesh
    head.position.y = 1.42
    visual_root.add_child(head)

func _physics_process(delta: float) -> void:
    var input_direction: Vector3 = _camera_relative_input()
    var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
    var desired_velocity: Vector3 = input_direction * WALK_SPEED
    var movement_force: Vector3 = (desired_velocity - horizontal_velocity) * (MASS_KG * RESPONSE)
    velocity += movement_force / MASS_KG * delta

    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    elif Input.is_key_pressed(KEY_SPACE):
        apply_impulse(Vector3.UP * JUMP_IMPULSE)

    if input_direction.length_squared() > 0.01:
        rotation.y = lerp_angle(rotation.y, atan2(-input_direction.x, -input_direction.z), minf(1.0, delta * 11.0))
        _play_walk()
    else:
        velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * delta * 4.0)
        velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * delta * 4.0)
        _play_idle_if_possible()

    move_and_slide()

    if sand != null:
        global_position = sand.clamp_inside(global_position)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _throw_projectile()

func apply_impulse(impulse: Vector3) -> void:
    velocity += impulse / MASS_KG

func _camera_relative_input() -> Vector3:
    var raw := Vector2(
        float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
        float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
    )
    if raw.length_squared() > 1.0:
        raw = raw.normalized()
    if raw.length_squared() < 0.001:
        return Vector3.ZERO

    var forward := Vector3(0.0, 0.0, -1.0)
    var right := Vector3(1.0, 0.0, 0.0)
    if aim_camera != null:
        forward = -aim_camera.global_basis.z
        forward.y = 0.0
        forward = forward.normalized()
        right = aim_camera.global_basis.x
        right.y = 0.0
        right = right.normalized()
    return (right * raw.x + forward * -raw.y).normalized()

func _throw_projectile() -> void:
    if throw_locked:
        return

    throw_locked = true
    _play_throw()

    var forward := -global_basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.0001:
        forward = Vector3.FORWARD
    else:
        forward = forward.normalized()

    await get_tree().create_timer(0.11).timeout
    if not is_inside_tree():
        return

    var orb := BombOrb.new()
    var right := global_basis.x
    get_tree().current_scene.add_child(orb)
    orb.global_position = global_position + Vector3.UP * 1.0 + forward * 0.48 + right * 0.15

    # Bombs are intentionally launched horizontally. Gravity may pull them
    # downward after release, but their own throw impulse never adds +Y motion.
    var throw_force := float(BombOrb.throw_force)
    var launch_velocity := forward * throw_force
    orb.apply_central_impulse(launch_velocity * orb.mass)

    await get_tree().create_timer(0.28).timeout
    throw_locked = false

func _aim_direction() -> Vector3:
    return -global_basis.z

func _discover_animations() -> void:
    if animation_player == null:
        return

    var animations = animation_player.get_animation_list()
    idle_animation = _find_animation_name(animations, ["idle", "standing", "stand"])
    walk_animation = _find_animation_name(animations, ["walk", "walking", "run"])
    throw_animation = _find_animation_name(animations, ["throw", "spell", "cast", "attack", "shoot"])
    animation_player.playback_default_blend_time = 0.12

    if idle_animation != "":
        animation_player.play(idle_animation, 0.0, 1.0)
    elif walk_animation != "":
        animation_player.play(walk_animation, 0.0, 1.0)
        animation_player.seek(0.0, true)
        animation_player.pause()

func _find_animation_name(animations: PackedStringArray, keywords: Array[String]) -> String:
    for keyword in keywords:
        for animation_name in animations:
            var lower := String(animation_name).to_lower()
            if lower.contains(keyword) and not lower.contains("back") and not lower.contains("left") and not lower.contains("right"):
                return String(animation_name)
    return ""

func _play_walk() -> void:
    if animation_player == null or walk_animation == "" or throw_locked:
        return
    if animation_player.current_animation != walk_animation or not animation_player.is_playing():
        animation_player.play(walk_animation, 0.14, 1.0)

func _play_idle_if_possible() -> void:
    if animation_player == null or throw_locked:
        return

    if idle_animation != "":
        if animation_player.current_animation != idle_animation or not animation_player.is_playing():
            animation_player.play(idle_animation, 0.16, 1.0)
        return

    if walk_animation != "" and animation_player.current_animation == walk_animation:
        animation_player.seek(0.0, true)
        animation_player.pause()

func _play_throw() -> void:
    if animation_player != null and throw_animation != "":
        animation_player.play(throw_animation, 0.06, 1.15)

func _find_animation_player(root: Node) -> AnimationPlayer:
    if root is AnimationPlayer:
        return root
    for child in root.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null
