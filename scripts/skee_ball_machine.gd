class_name SkeeBallMachine
extends Node3D

signal scored(points: int, ball: SkeeBallBall)

const BALL_START_LOCAL := Vector3(0.0, 0.76, 4.05)
const TARGET_CENTER := Vector3(0.0, 1.10, -3.67)
const LEFT_100 := Vector3(-1.14, 1.10, -4.42)
const RIGHT_100 := Vector3(1.14, 1.10, -4.42)

var cabinet_material: StandardMaterial3D
var blue_material: StandardMaterial3D
var gold_material: StandardMaterial3D
var lane_material: StandardMaterial3D
var target_material: StandardMaterial3D
var metal_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var net_material: StandardMaterial3D

var target_balls: Dictionary = {}

func _ready() -> void:
    _build_materials()
    _build_cabinet()
    _build_lane_and_ramp()
    _build_target_deck()
    _build_backboard_and_net()

func ball_start_transform() -> Transform3D:
    return Transform3D(Basis.IDENTITY, to_global(BALL_START_LOCAL))

func _physics_process(_delta: float) -> void:
    for candidate in target_balls.keys():
        if not is_instance_valid(candidate):
            target_balls.erase(candidate)
            continue
        if not (candidate is SkeeBallBall):
            continue

        var ball := candidate as SkeeBallBall
        if ball.scored or not ball.launched:
            continue
        if ball.global_position.y > 1.34 or ball.linear_velocity.y > 0.6:
            continue

        var points := _score_for_position(to_local(ball.global_position))
        if points <= 0:
            continue

        ball.mark_scored()
        target_balls.erase(candidate)
        scored.emit(points, ball)

func _build_materials() -> void:
    cabinet_material = _material(Color(0.30, 0.055, 0.035), 0.72)
    blue_material = _material(Color(0.075, 0.22, 0.34), 0.68)
    gold_material = _material(Color(0.82, 0.51, 0.08), 0.46, 0.15)
    lane_material = _material(Color(0.18, 0.42, 0.27), 0.78)
    target_material = _material(Color(0.62, 0.095, 0.075), 0.75)
    metal_material = _material(Color(0.78, 0.78, 0.74), 0.38, 0.18)
    dark_material = _material(Color(0.035, 0.045, 0.052), 0.82)
    net_material = _material(Color(0.52, 0.58, 0.61), 0.60, 0.10)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _build_cabinet() -> void:
    _add_static_box(
        "LeftCabinet",
        Vector3(0.42, 1.55, 8.9),
        Vector3(-1.47, 0.72, 0.15),
        cabinet_material
    )
    _add_static_box(
        "RightCabinet",
        Vector3(0.42, 1.55, 8.9),
        Vector3(1.47, 0.72, 0.15),
        cabinet_material
    )

    _add_static_box(
        "LeftBackTower",
        Vector3(0.46, 4.45, 1.55),
        Vector3(-1.47, 2.18, -4.32),
        cabinet_material
    )
    _add_static_box(
        "RightBackTower",
        Vector3(0.46, 4.45, 1.55),
        Vector3(1.47, 2.18, -4.32),
        cabinet_material
    )

    _add_static_box(
        "FrontLeftPedestal",
        Vector3(0.72, 1.20, 1.10),
        Vector3(-1.14, 0.55, 4.15),
        cabinet_material
    )
    _add_static_box(
        "FrontRightPedestal",
        Vector3(0.72, 1.20, 1.10),
        Vector3(1.14, 0.55, 4.15),
        cabinet_material
    )

    _add_visual_box(
        "LeftGoldTrim",
        Vector3(0.09, 0.10, 7.6),
        Vector3(-1.22, 1.05, 0.05),
        gold_material
    )
    _add_visual_box(
        "RightGoldTrim",
        Vector3(0.09, 0.10, 7.6),
        Vector3(1.22, 1.05, 0.05),
        gold_material
    )

func _build_lane_and_ramp() -> void:
    var profile: Array[Vector2] = [
        Vector2(4.55, 0.56),
        Vector2(1.20, 0.56),
        Vector2(0.10, 0.57),
        Vector2(-0.75, 0.61),
        Vector2(-1.25, 0.72),
        Vector2(-1.62, 0.90),
        Vector2(-1.90, 1.13),
        Vector2(-2.14, 1.43),
    ]
    var half_width := 1.10

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(lane_material)

    for i in range(profile.size() - 1):
        var current := profile[i]
        var next := profile[i + 1]
        var left_current := Vector3(-half_width, current.y, current.x)
        var right_current := Vector3(half_width, current.y, current.x)
        var left_next := Vector3(-half_width, next.y, next.x)
        var right_next := Vector3(half_width, next.y, next.x)

        surface.add_vertex(left_current)
        surface.add_vertex(right_current)
        surface.add_vertex(right_next)
        surface.add_vertex(left_current)
        surface.add_vertex(right_next)
        surface.add_vertex(left_next)

    surface.generate_normals()
    var lane_mesh := surface.commit()

    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "RunwayAndRamp"
    mesh_instance.mesh = lane_mesh
    add_child(mesh_instance)

    var body := StaticBody3D.new()
    body.name = "RunwayCollision"
    body.collision_layer = 1
    body.collision_mask = 1
    add_child(body)

    var collision := CollisionShape3D.new()
    collision.shape = lane_mesh.create_trimesh_shape()
    body.add_child(collision)

    _add_static_box(
        "LeftLaneRail",
        Vector3(0.16, 0.32, 6.20),
        Vector3(-1.18, 0.78, 1.15),
        gold_material
    )
    _add_static_box(
        "RightLaneRail",
        Vector3(0.16, 0.32, 6.20),
        Vector3(1.18, 0.78, 1.15),
        gold_material
    )

func _build_target_deck() -> void:
    _add_static_box(
        "TargetDeck",
        Vector3(3.05, 0.14, 2.34),
        Vector3(0.0, 1.02, -3.74),
        target_material
    )

    _add_ring(TARGET_CENTER, 1.08, 0.24, 0.10, 24, 10)
    _add_ring(TARGET_CENTER, 0.79, 0.28, 0.09, 20, 20)
    _add_ring(TARGET_CENTER, 0.55, 0.32, 0.085, 18, 30)
    _add_ring(TARGET_CENTER, 0.34, 0.38, 0.08, 16, 50)
    _add_ring(LEFT_100, 0.31, 0.42, 0.075, 16, 100)
    _add_ring(RIGHT_100, 0.31, 0.42, 0.075, 16, 100)

    var score_area := Area3D.new()
    score_area.name = "ScorePlane"
    score_area.collision_layer = 0
    score_area.collision_mask = 1
    score_area.monitoring = true
    add_child(score_area)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(3.10, 0.06, 2.40)
    collision.shape = shape
    collision.position = Vector3(0.0, 1.11, -3.74)
    score_area.add_child(collision)
    score_area.body_entered.connect(_on_score_area_entered)
    score_area.body_exited.connect(_on_score_area_exited)

func _build_backboard_and_net() -> void:
    _add_static_box(
        "Backboard",
        Vector3(3.05, 2.35, 0.18),
        Vector3(0.0, 2.73, -5.00),
        blue_material
    )
    _add_visual_box(
        "Marquee",
        Vector3(3.15, 0.86, 0.22),
        Vector3(0.0, 4.12, -4.98),
        blue_material
    )
    _add_visual_box(
        "MarqueeGoldTop",
        Vector3(3.25, 0.10, 0.26),
        Vector3(0.0, 4.58, -4.96),
        gold_material
    )

    var title := Label3D.new()
    title.text = "SLOT BALL"
    title.font_size = 82
    title.modulate = Color(0.95, 0.74, 0.18)
    title.outline_size = 14
    title.outline_modulate = Color(0.32, 0.055, 0.035)
    title.position = Vector3(0.0, 3.18, -4.88)
    add_child(title)

    for x_index in range(-3, 4):
        _add_visual_box(
            "NetV_%d" % x_index,
            Vector3(0.025, 1.70, 0.025),
            Vector3(float(x_index) * 0.38, 2.28, -4.72),
            net_material,
            Vector3(0.0, 0.0, deg_to_rad(8.0))
        )
    for y_index in range(5):
        _add_visual_box(
            "NetH_%d" % y_index,
            Vector3(2.65, 0.025, 0.025),
            Vector3(0.0, 1.60 + float(y_index) * 0.35, -4.70),
            net_material,
            Vector3(0.0, 0.0, deg_to_rad(-8.0))
        )

    _add_visual_box(
        "NetFrameLeft",
        Vector3(0.10, 2.00, 0.10),
        Vector3(-1.38, 2.35, -4.64),
        gold_material
    )
    _add_visual_box(
        "NetFrameRight",
        Vector3(0.10, 2.00, 0.10),
        Vector3(1.38, 2.35, -4.64),
        gold_material
    )
    _add_visual_box(
        "NetFrameTop",
        Vector3(2.86, 0.10, 0.10),
        Vector3(0.0, 3.35, -4.64),
        gold_material
    )

func _add_ring(
    center: Vector3,
    radius: float,
    height: float,
    thickness: float,
    segments: int,
    score: int
) -> void:
    var segment_length := 2.0 * radius * sin(PI / float(segments)) * 1.12
    for index in range(segments):
        var angle := TAU * float(index) / float(segments)
        var position := Vector3(
            center.x + cos(angle) * radius,
            1.10 + height * 0.5,
            center.z + sin(angle) * radius
        )
        _add_static_box(
            "Ring_%d_%02d" % [score, index],
            Vector3(segment_length, height, thickness),
            position,
            metal_material,
            Vector3(0.0, angle + PI * 0.5, 0.0)
        )

    var label := Label3D.new()
    label.text = str(score)
    label.font_size = 42 if score < 100 else 34
    label.modulate = Color(0.08, 0.08, 0.08)
    label.outline_size = 4
    label.outline_modulate = Color(0.90, 0.88, 0.80)
    label.position = Vector3(center.x, 1.10 + height + 0.08, center.z + radius)
    add_child(label)

func _score_for_position(local_position: Vector3) -> int:
    var planar := Vector2(local_position.x, local_position.z)
    var left_100 := Vector2(LEFT_100.x, LEFT_100.z)
    var right_100 := Vector2(RIGHT_100.x, RIGHT_100.z)
    if planar.distance_to(left_100) <= 0.36 or planar.distance_to(right_100) <= 0.36:
        return 100

    var center := Vector2(TARGET_CENTER.x, TARGET_CENTER.z)
    var distance := planar.distance_to(center)
    if distance <= 0.30:
        return 50
    if distance <= 0.52:
        return 40
    if distance <= 0.76:
        return 30
    if distance <= 1.03:
        return 20
    if distance <= 1.24:
        return 10
    return 0

func _on_score_area_entered(body: Node3D) -> void:
    if body is SkeeBallBall:
        target_balls[body] = true

func _on_score_area_exited(body: Node3D) -> void:
    target_balls.erase(body)

func _add_static_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    material: Material,
    rotation_value: Vector3 = Vector3.ZERO
) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = position
    body.rotation = rotation_value
    body.collision_layer = 1
    body.collision_mask = 1
    add_child(body)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    mesh_instance.mesh = mesh
    body.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    return body

func _add_visual_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    material: Material,
    rotation_value: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = node_name
    mesh_instance.position = position
    mesh_instance.rotation = rotation_value
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    mesh_instance.mesh = mesh
    add_child(mesh_instance)
    return mesh_instance
