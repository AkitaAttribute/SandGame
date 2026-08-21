class_name SandChunk
extends RigidBody3D

var sand: SandField
var deposit_amount := 0.02
var grain_color := Color.WHITE
var age := 0.0
var settled := false

func _ready() -> void:
    mass = 0.035
    linear_damp = 0.04
    angular_damp = 0.10
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 4

    var mesh_instance := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.095
    sphere.height = 0.19
    sphere.radial_segments = 6
    sphere.rings = 4
    var material := StandardMaterial3D.new()
    material.albedo_color = grain_color
    material.roughness = 0.96
    sphere.material = material
    mesh_instance.mesh = sphere
    add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 0.09
    collision.shape = shape
    add_child(collision)

    var physics_material := PhysicsMaterial.new()
    physics_material.friction = 0.72
    physics_material.bounce = 0.10
    physics_material_override = physics_material

func _physics_process(delta: float) -> void:
    if settled:
        return
    age += delta
    if sand == null:
        if age > 6.0:
            queue_free()
        return

    var surface: float = sand.surface_height_at(global_position)
    var near_surface: bool = global_position.y <= surface + 0.14
    var slow_vertical: bool = absf(linear_velocity.y) <= 1.2
    var slow_horizontal: bool = Vector2(linear_velocity.x, linear_velocity.z).length() <= 2.8
    if age > 0.48 and near_surface and slow_vertical and slow_horizontal:
        _settle()
    elif age > 6.0:
        _settle()

func _settle() -> void:
    if settled:
        return
    settled = true
    sand.deposit(global_position, deposit_amount, grain_color)
    queue_free()
