class_name BombOrb
extends RigidBody3D

const BLUE := Color(0.08, 0.42, 1.0)
const RED := Color(1.0, 0.08, 0.05)
const ORB_RADIUS := 0.17

const DEFAULT_THROW_FORCE := 15
const DEFAULT_EXPLOSION_FORCE := 250
const DEFAULT_BLAST_RADIUS := 2.7
const DEFAULT_FUSE_DURATION := 3

static var throw_force: int = DEFAULT_THROW_FORCE
static var explosion_force: int = DEFAULT_EXPLOSION_FORCE
static var blast_radius: float = DEFAULT_BLAST_RADIUS
static var fuse_duration: int = DEFAULT_FUSE_DURATION

var elapsed := 0.0
var flash_phase := 0.0
var exploded := false
var material: StandardMaterial3D
var sand: SandField

func _ready() -> void:
    add_to_group("physics_projectiles")
    collision_layer = 1
    collision_mask = 1
    mass = 0.45
    linear_damp = 0.22
    angular_damp = 0.28
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 4

    sand = get_tree().get_first_node_in_group("sand") as SandField

    var mesh_instance := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = ORB_RADIUS
    sphere.height = ORB_RADIUS * 2.0
    sphere.radial_segments = 12
    sphere.rings = 7

    material = StandardMaterial3D.new()
    material.albedo_color = BLUE
    material.emission_enabled = true
    material.emission = BLUE * 0.6
    material.emission_energy_multiplier = 0.85
    material.roughness = 0.42
    sphere.material = material

    mesh_instance.mesh = sphere
    add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = ORB_RADIUS
    collision.shape = shape
    add_child(collision)

    var physics_material := PhysicsMaterial.new()
    physics_material.friction = 0.88
    physics_material.bounce = 0.0
    physics_material_override = physics_material

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    # The bomb is intentionally one-way in Y: gravity may move it downward and
    # collision support may stop that descent, but no contact/impulse may turn
    # its vertical velocity positive and launch it upward.
    var body_velocity := state.linear_velocity
    if body_velocity.y > 0.0:
        body_velocity.y = 0.0
        state.linear_velocity = body_velocity

func _physics_process(delta: float) -> void:
    if exploded:
        return

    if sand == null:
        sand = get_tree().get_first_node_in_group("sand") as SandField
        return

    var current_velocity := linear_velocity
    if current_velocity.y > 0.0:
        current_velocity.y = 0.0
        linear_velocity = current_velocity

    var reaction_impulse: Vector3 = sand.interact_sphere(
        global_position,
        ORB_RADIUS,
        linear_velocity,
        mass,
        delta
    )

    # Upward grain support is allowed only far enough to cancel existing
    # downward velocity. It can never reverse the bomb into upward motion.
    if reaction_impulse.y > 0.0:
        var max_upward_impulse := maxf(0.0, -linear_velocity.y * mass)
        reaction_impulse.y = minf(reaction_impulse.y, max_upward_impulse)

    if reaction_impulse.length_squared() > 0.0000001:
        apply_central_impulse(reaction_impulse)

func _process(delta: float) -> void:
    if exploded:
        return

    elapsed += delta
    var fuse_time := maxf(1.0, float(BombOrb.fuse_duration))
    var progress: float = clampf(elapsed / fuse_time, 0.0, 1.0)
    var flashes_per_second: float = lerpf(
        1.4,
        17.0,
        pow(progress, 3.15)
    )
    flash_phase += delta * flashes_per_second

    var red_now: bool = (
        fmod(flash_phase, 1.0) < lerpf(0.24, 0.48, progress)
    )
    var color: Color = RED if red_now else BLUE
    material.albedo_color = color
    material.emission = color * (0.85 if red_now else 0.55)

    if elapsed >= fuse_time:
        _detonate()

func _detonate() -> void:
    if exploded:
        return

    exploded = true

    if sand == null:
        sand = get_tree().get_first_node_in_group("sand") as SandField
    if sand != null:
        sand.apply_radial_impulse(
            global_position,
            maxf(0.1, BombOrb.blast_radius),
            float(BombOrb.explosion_force)
        )

    for node in get_tree().get_nodes_in_group("player"):
        if node is PlayerController:
            var offset: Vector3 = node.global_position - global_position
            var distance: float = maxf(0.35, offset.length())
            if distance < 4.8:
                var falloff: float = pow(1.0 - distance / 4.8, 2.0)
                var direction: Vector3 = (
                    offset.normalized() + Vector3.UP * 0.42
                ).normalized()
                node.apply_impulse(direction * 54.0 * falloff)

    for node in get_tree().get_nodes_in_group("physics_projectiles"):
        if node == self or not (node is RigidBody3D):
            continue
        var offset: Vector3 = node.global_position - global_position
        var distance: float = maxf(0.35, offset.length())
        if distance < 4.2:
            var falloff: float = pow(1.0 - distance / 4.2, 2.0)
            node.apply_central_impulse(
                (offset.normalized() + Vector3.UP * 0.3).normalized()
                * 8.0
                * falloff
            )

    queue_free()
