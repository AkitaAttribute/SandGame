class_name SkeeBallBall
extends RigidBody3D

const BASE_RADIUS := 1.625 * 0.0254
const GAME_SCALE := 4.0
const RADIUS := BASE_RADIUS * GAME_SCALE
const MASS_KG := 0.25
const OUT_OF_BOUNDS_Y := -1.0
const QUIET_SPEED := 0.18
const QUIET_TIME_TO_RESET := 2.2

var start_transform := Transform3D.IDENTITY
var launched := false
var scored := false
var quiet_time := 0.0

func _ready() -> void:
    collision_layer = 1
    collision_mask = 1
    mass = MASS_KG
    gravity_scale = 0.0
    linear_damp = 0.06
    angular_damp = 0.08
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 8

    var mesh_instance := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = RADIUS
    sphere.height = RADIUS * 2.0
    sphere.radial_segments = 24
    sphere.rings = 14

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.86, 0.19, 0.13)
    material.roughness = 0.42
    sphere.material = material
    mesh_instance.mesh = sphere
    add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = RADIUS
    collision.shape = shape
    add_child(collision)

    var physics_material := PhysicsMaterial.new()
    physics_material.friction = 0.72
    physics_material.bounce = 0.04
    physics_material_override = physics_material
    freeze = true

func configure_start(value: Transform3D) -> void:
    start_transform = value
    reset_to_start()

func reset_to_start() -> void:
    freeze = true
    sleeping = false
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    global_transform = start_transform
    launched = false
    scored = false
    quiet_time = 0.0

func is_waiting() -> bool:
    return not launched and not scored

func launch(direction: Vector3, speed: float) -> void:
    if not is_waiting():
        return

    var launch_direction := direction
    launch_direction.y = 0.0
    if launch_direction.length_squared() < 0.0001:
        launch_direction = Vector3.FORWARD
    launch_direction = launch_direction.normalized()

    freeze = false
    sleeping = false
    launched = true
    quiet_time = 0.0
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    apply_central_impulse(launch_direction * maxf(speed, 0.0) * mass)

func mark_scored() -> void:
    if scored:
        return
    scored = true
    launched = false
    freeze = true
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    if freeze:
        return

    var body_velocity := state.linear_velocity
    body_velocity.y -= maxf(0.0, SkeeBallSettings.gravity) * state.step
    state.linear_velocity = body_velocity

func _physics_process(delta: float) -> void:
    if not launched:
        return

    if (
        global_position.y < OUT_OF_BOUNDS_Y
        or absf(global_position.x) > 10.0
        or global_position.z < -14.0
        or global_position.z > 16.0
    ):
        reset_to_start()
        return

    if linear_velocity.length() <= QUIET_SPEED and angular_velocity.length() <= 0.8:
        quiet_time += delta
    else:
        quiet_time = 0.0

    if quiet_time >= QUIET_TIME_TO_RESET:
        reset_to_start()
