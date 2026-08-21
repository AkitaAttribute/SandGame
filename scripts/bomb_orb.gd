class_name BombOrb
extends RigidBody3D

const FUSE_TIME := 3.0
const BLUE := Color(0.08, 0.42, 1.0)
const RED := Color(1.0, 0.08, 0.05)

var elapsed := 0.0
var flash_phase := 0.0
var exploded := false
var material: StandardMaterial3D

func _ready() -> void:
    add_to_group("physics_projectiles")
    mass = 1.0
    linear_damp = 0.22
    angular_damp = 0.28
    contact_monitor = true
    max_contacts_reported = 4

    var mesh_instance := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.17
    sphere.height = 0.34
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
    shape.radius = 0.17
    collision.shape = shape
    add_child(collision)

    var physics_material := PhysicsMaterial.new()
    physics_material.friction = 0.88
    physics_material.bounce = 0.12
    physics_material_override = physics_material

func _process(delta: float) -> void:
    if exploded:
        return
    elapsed += delta
    var progress: float = clampf(elapsed / FUSE_TIME, 0.0, 1.0)
    var flashes_per_second: float = lerpf(1.4, 17.0, pow(progress, 3.15))
    flash_phase += delta * flashes_per_second
    var red_now: bool = fmod(flash_phase, 1.0) < lerpf(0.24, 0.48, progress)
    var color: Color = RED if red_now else BLUE
    material.albedo_color = color
    material.emission = color * (0.85 if red_now else 0.55)

    if elapsed >= FUSE_TIME:
        _explode()

func _explode() -> void:
    if exploded:
        return
    exploded = true
    var sand := get_tree().get_first_node_in_group("sand") as SandField
    if sand != null:
        sand.apply_explosion(global_position, 2.7, 12.5)

    for node in get_tree().get_nodes_in_group("player"):
        if node is PlayerController:
            var offset: Vector3 = node.global_position - global_position
            var distance: float = maxf(0.35, offset.length())
            if distance < 4.8:
                var falloff: float = pow(1.0 - distance / 4.8, 2.0)
                var direction: Vector3 = (offset.normalized() + Vector3.UP * 0.42).normalized()
                node.apply_impulse(direction * 54.0 * falloff)

    for node in get_tree().get_nodes_in_group("physics_projectiles"):
        if node == self or not (node is RigidBody3D):
            continue
        var offset: Vector3 = node.global_position - global_position
        var distance: float = maxf(0.35, offset.length())
        if distance < 4.2:
            var falloff: float = pow(1.0 - distance / 4.2, 2.0)
            node.apply_central_impulse((offset.normalized() + Vector3.UP * 0.3).normalized() * 8.0 * falloff)

    queue_free()
