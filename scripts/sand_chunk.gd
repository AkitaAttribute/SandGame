class_name SandChunk
extends RigidBody3D

var sand: SandField
var deposit_amount := 0.02
var grain_color := Color.WHITE
var age := 0.0
var settled := false

func _ready() -> void:
    mass = 0.05
    linear_damp = 0.10
    angular_damp = 0.15
    contact_monitor = true
    max_contacts_reported = 2

    var mesh_instance := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.075
    sphere.height = 0.15
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
    shape.radius = 0.072
    collision.shape = shape
    add_child(collision)

    var physics_material := PhysicsMaterial.new()
    physics_material.friction = 0.82
    physics_material.bounce = 0.08
    physics_material_override = physics_material

func _physics_process(delta: float) -> void:
    if settled:
        return
    age += delta
    if sand == null:
        if age > 4.0:
            queue_free()
        return

    var surface := sand.surface_height_at(global_position)
    if age > 0.35 and ((global_position.y <= surface + 0.13 and linear_velocity.y <= 0.8) or sleeping or age > 3.5):
        settled = true
        sand.deposit(global_position, deposit_amount, grain_color)
        queue_free()
