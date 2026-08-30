class_name SkeeBallMachine
extends Node3D

signal scored(points: int, ball: SkeeBallBall)

const GAME_SCALE := 4.0
const INCH := 0.0254
const OVERALL_WIDTH := 30.0 * INCH
const OVERALL_LENGTH := 123.0 * INCH
const OVERALL_HEIGHT := 85.0 * INCH
const ALLEY_WIDTH := 29.0 * INCH
const ALLEY_LENGTH := 87.0 * INCH
const ALLEY_HEIGHT := 26.0 * INCH
const PLAYFIELD_DEPTH := 40.0 * INCH
const ROLLING_WIDTH := 24.5 * INCH
const BUMPER_GAP := 18.25 * INCH
const TARGET_WIDTH := 27.5 * INCH
const TARGET_LENGTH := 38.0 * INCH
const TARGET_HOLE_RADIUS := 2.0 * INCH
const LANE_SLOPE := deg_to_rad(4.0)
const TARGET_ANGLE := deg_to_rad(50.0)
const LANE_SLAB_THICKNESS := 0.042
const TARGET_BOARD_THICKNESS := 0.038
const HOLE_WALL_THICKNESS := 0.012

const FRONT_Z := OVERALL_LENGTH * 0.5
const BACK_Z := -OVERALL_LENGTH * 0.5
const ALLEY_REAR_Z := FRONT_Z - ALLEY_LENGTH
const LANE_FRONT_Z := FRONT_Z - 0.07
const HOP_START_Z := ALLEY_REAR_Z + 0.30
const HOP_END_Z := ALLEY_REAR_Z + 0.02
const LANE_FRONT_Y := 0.405
const TARGET_BOTTOM := Vector3(0.0, 0.635, -0.92)
const TARGET_V := Vector3(0.0, sin(TARGET_ANGLE), -cos(TARGET_ANGLE))
const TARGET_N := Vector3(0.0, cos(TARGET_ANGLE), sin(TARGET_ANGLE))
const TARGET_RIGHT := Vector3.RIGHT

const V10 := 6.375 * INCH
const V20 := 11.875 * INCH
const V30 := 16.875 * INCH
const V40 := 24.125 * INCH
const V50 := 30.375 * INCH
const V100 := 34.625 * INCH
const HUNDO_X := 10.0 * INCH
const BALL_START_LOCAL := Vector3(0.0, 0.0, 1.35)

var cabinet_material: StandardMaterial3D
var blue_material: StandardMaterial3D
var gold_material: StandardMaterial3D
var cork_material: StandardMaterial3D
var target_material: StandardMaterial3D
var hole_material: StandardMaterial3D
var hole_void_material: StandardMaterial3D
var rubber_material: StandardMaterial3D
var lane_physics_material: PhysicsMaterial
var target_physics_material: PhysicsMaterial

func _ready() -> void:
    scale = Vector3.ONE * GAME_SCALE
    _build_materials()
    _build_alley_cabinet()
    _build_lane_and_ball_hop()
    _build_playfield_cabinet()
    _build_target_board()
    _build_backboard()
    _build_invisible_containment()

func ball_start_transform() -> Transform3D:
    var z := BALL_START_LOCAL.z
    var y := _straight_lane_y(z) + SkeeBallBall.BASE_RADIUS + 0.004
    return Transform3D(Basis.IDENTITY, to_global(Vector3(0.0, y, z)))

func _build_materials() -> void:
    cabinet_material = _material(Color(0.32, 0.060, 0.038), 0.70)
    blue_material = _material(Color(0.070, 0.19, 0.29), 0.68)
    gold_material = _material(Color(0.78, 0.47, 0.07), 0.46, 0.10)
    cork_material = _material(Color(0.39, 0.45, 0.30), 0.92)
    target_material = _material(Color(0.56, 0.105, 0.075), 0.84)
    hole_material = _material(Color(0.91, 0.90, 0.86), 0.48, 0.04)
    hole_void_material = _material(Color(0.008, 0.008, 0.010), 0.96)
    rubber_material = _material(Color(0.025, 0.026, 0.027), 0.94)

    lane_physics_material = PhysicsMaterial.new()
    lane_physics_material.friction = 0.88
    lane_physics_material.bounce = 0.02

    target_physics_material = PhysicsMaterial.new()
    target_physics_material.friction = 0.72
    target_physics_material.bounce = 0.04

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _build_alley_cabinet() -> void:
    var side_thickness := 0.055
    var center_z := (FRONT_Z + ALLEY_REAR_Z) * 0.5
    var panel_length := FRONT_Z - ALLEY_REAR_Z
    var side_x := ALLEY_WIDTH * 0.5 - side_thickness * 0.5

    _add_static_box("AlleyLeftSide", Vector3(side_thickness, ALLEY_HEIGHT, panel_length), Vector3(-side_x, ALLEY_HEIGHT * 0.5, center_z), cabinet_material)
    _add_static_box("AlleyRightSide", Vector3(side_thickness, ALLEY_HEIGHT, panel_length), Vector3(side_x, ALLEY_HEIGHT * 0.5, center_z), cabinet_material)
    _add_static_box("FrontFace", Vector3(ALLEY_WIDTH, 0.42, 0.075), Vector3(0.0, 0.21, FRONT_Z - 0.035), cabinet_material)
    _add_visual_box("FrontInset", Vector3(ALLEY_WIDTH - 0.18, 0.30, 0.012), Vector3(0.0, 0.23, FRONT_Z - 0.078), blue_material)

    var straight_len := LANE_FRONT_Z - HOP_START_Z
    var center_lane_z := (LANE_FRONT_Z + HOP_START_Z) * 0.5
    var center_lane_y := (_straight_lane_y(LANE_FRONT_Z) + _straight_lane_y(HOP_START_Z)) * 0.5
    var rail_x := ROLLING_WIDTH * 0.5 + 0.030
    for side in [-1.0, 1.0]:
        _add_static_box(
            "GoldChannel_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.050, 0.050, straight_len),
            Vector3(side * rail_x, center_lane_y + 0.045, center_lane_z),
            gold_material,
            Vector3(LANE_SLOPE, 0.0, 0.0)
        )

func _straight_lane_y(z: float) -> float:
    return LANE_FRONT_Y + (LANE_FRONT_Z - z) * tan(LANE_SLOPE)

func _build_lane_and_ball_hop() -> void:
    var profile: Array[Vector2] = [
        Vector2(LANE_FRONT_Z, _straight_lane_y(LANE_FRONT_Z)),
        Vector2(0.90, _straight_lane_y(0.90)),
        Vector2(0.30, _straight_lane_y(0.30)),
        Vector2(HOP_START_Z, _straight_lane_y(HOP_START_Z)),
    ]

    var hop_y := _straight_lane_y(HOP_START_Z)
    profile.append(Vector2(HOP_START_Z - 0.070, hop_y + 0.006))
    profile.append(Vector2(HOP_START_Z - 0.135, hop_y + 0.021))
    profile.append(Vector2(HOP_START_Z - 0.195, hop_y + 0.047))
    profile.append(Vector2(HOP_START_Z - 0.245, hop_y + 0.082))
    profile.append(Vector2(HOP_END_Z, hop_y + 0.126))

    for index in range(profile.size() - 1):
        _add_lane_segment("LaneSlab_%02d" % index, profile[index], profile[index + 1])

    var bumper_thickness := 0.025
    var bumper_x := BUMPER_GAP * 0.5 + bumper_thickness * 0.5
    var bumper_len := LANE_FRONT_Z - HOP_START_Z
    var bumper_z := (LANE_FRONT_Z + HOP_START_Z) * 0.5
    var bumper_y := (_straight_lane_y(LANE_FRONT_Z) + _straight_lane_y(HOP_START_Z)) * 0.5 + 0.042
    for side in [-1.0, 1.0]:
        _add_static_box(
            "HardRubberBumper_%s" % ("L" if side < 0.0 else "R"),
            Vector3(bumper_thickness, 0.065, bumper_len),
            Vector3(side * bumper_x, bumper_y, bumper_z),
            rubber_material,
            Vector3(LANE_SLOPE, 0.0, 0.0),
            lane_physics_material
        )

func _add_lane_segment(node_name: String, a: Vector2, b: Vector2) -> void:
    var delta_z := b.x - a.x
    var delta_y := b.y - a.y
    var segment_length := sqrt(delta_z * delta_z + delta_y * delta_y)
    if segment_length <= 0.0001:
        return

    var angle := atan2(absf(delta_y), absf(delta_z))
    var basis := Basis.from_euler(Vector3(angle, 0.0, 0.0))
    var top_center := Vector3(0.0, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5)
    var center := top_center - basis.y * (LANE_SLAB_THICKNESS * 0.5)
    _add_oriented_static_box(
        node_name,
        Vector3(ROLLING_WIDTH, LANE_SLAB_THICKNESS, segment_length + 0.004),
        center,
        basis,
        cork_material,
        lane_physics_material
    )

func _build_playfield_cabinet() -> void:
    var head_front_z := ALLEY_REAR_Z + 0.10
    var head_depth := PLAYFIELD_DEPTH
    var head_center_z := head_front_z - head_depth * 0.5
    var side_thickness := 0.055
    var side_x := ALLEY_WIDTH * 0.5 - side_thickness * 0.5

    _add_static_box("HeadLeftSide", Vector3(side_thickness, OVERALL_HEIGHT, head_depth), Vector3(-side_x, OVERALL_HEIGHT * 0.5, head_center_z), cabinet_material)
    _add_static_box("HeadRightSide", Vector3(side_thickness, OVERALL_HEIGHT, head_depth), Vector3(side_x, OVERALL_HEIGHT * 0.5, head_center_z), cabinet_material)
    _add_static_box("HeadBack", Vector3(ALLEY_WIDTH, OVERALL_HEIGHT, 0.050), Vector3(0.0, OVERALL_HEIGHT * 0.5, BACK_Z + 0.025), cabinet_material)

func _target_holes() -> Array[Dictionary]:
    return [
        {"points": 10, "u": 0.0, "v": V10},
        {"points": 20, "u": 0.0, "v": V20},
        {"points": 30, "u": 0.0, "v": V30},
        {"points": 40, "u": 0.0, "v": V40},
        {"points": 50, "u": 0.0, "v": V50},
        {"points": 100, "u": -HUNDO_X, "v": V100},
        {"points": 100, "u": HUNDO_X, "v": V100},
    ]

func _target_point(u: float, v: float, normal_offset: float = 0.0) -> Vector3:
    return TARGET_BOTTOM + TARGET_RIGHT * u + TARGET_V * v + TARGET_N * normal_offset

func _build_target_board() -> void:
    var columns := 72
    var rows := 104
    var du := TARGET_WIDTH / float(columns)
    var dv := TARGET_LENGTH / float(rows)
    var holes := _target_holes()
    var cut_radius := TARGET_HOLE_RADIUS + HOLE_WALL_THICKNESS + maxf(du, dv) * 0.55

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(target_material)

    var front_offset := 0.0
    var back_offset := -TARGET_BOARD_THICKNESS
    for row in range(rows):
        var v0 := float(row) * dv
        var v1 := float(row + 1) * dv
        for column in range(columns):
            var u0 := -TARGET_WIDTH * 0.5 + float(column) * du
            var u1 := u0 + du
            var center_u := (u0 + u1) * 0.5
            var center_v := (v0 + v1) * 0.5
            if _inside_target_hole(center_u, center_v, holes, cut_radius):
                continue

            var fa := _target_point(u0, v0, front_offset)
            var fb := _target_point(u1, v0, front_offset)
            var fc := _target_point(u1, v1, front_offset)
            var fd := _target_point(u0, v1, front_offset)
            _add_quad(surface, fa, fb, fc, fd)

            var ba := _target_point(u0, v0, back_offset)
            var bb := _target_point(u1, v0, back_offset)
            var bc := _target_point(u1, v1, back_offset)
            var bd := _target_point(u0, v1, back_offset)
            _add_quad(surface, bd, bc, bb, ba)

    surface.generate_normals()
    var board_mesh := surface.commit()

    var board_instance := MeshInstance3D.new()
    board_instance.name = "PerforatedTargetBoard"
    board_instance.mesh = board_mesh
    add_child(board_instance)

    var board_body := StaticBody3D.new()
    board_body.name = "TargetBoardCollision"
    board_body.collision_layer = 1
    board_body.collision_mask = 1
    board_body.physics_material_override = target_physics_material
    add_child(board_body)

    var board_collision := CollisionShape3D.new()
    board_collision.shape = board_mesh.create_trimesh_shape()
    board_body.add_child(board_collision)

    _add_target_board_perimeter()

    for hole in holes:
        var points := int(hole["points"])
        var u := float(hole["u"])
        var v := float(hole["v"])
        _add_hole_sleeve(u, v, points)
        _add_hole_void(u, v, points)
        _add_hole_label(u, v, points)
        _add_score_reset_point(points, u, v)

func _inside_target_hole(u: float, v: float, holes: Array[Dictionary], radius: float) -> bool:
    for hole in holes:
        var delta_u := u - float(hole["u"])
        var delta_v := v - float(hole["v"])
        if delta_u * delta_u + delta_v * delta_v <= radius * radius:
            return true
    return false

func _add_target_board_perimeter() -> void:
    var basis := Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    var half_w := TARGET_WIDTH * 0.5
    var half_l := TARGET_LENGTH * 0.5
    var edge := 0.020
    var depth_center := -TARGET_BOARD_THICKNESS * 0.5

    _add_oriented_static_box("TargetEdgeLeft", Vector3(edge, TARGET_BOARD_THICKNESS, TARGET_LENGTH), _target_point(-half_w, half_l, depth_center), basis, target_material, target_physics_material)
    _add_oriented_static_box("TargetEdgeRight", Vector3(edge, TARGET_BOARD_THICKNESS, TARGET_LENGTH), _target_point(half_w, half_l, depth_center), basis, target_material, target_physics_material)
    _add_oriented_static_box("TargetEdgeBottom", Vector3(TARGET_WIDTH, TARGET_BOARD_THICKNESS, edge), _target_point(0.0, 0.0, depth_center), basis, target_material, target_physics_material)
    _add_oriented_static_box("TargetEdgeTop", Vector3(TARGET_WIDTH, TARGET_BOARD_THICKNESS, edge), _target_point(0.0, TARGET_LENGTH, depth_center), basis, target_material, target_physics_material)

func _add_hole_sleeve(u: float, v: float, points: int) -> void:
    var segments := 28
    var radius := TARGET_HOLE_RADIUS + HOLE_WALL_THICKNESS * 0.5
    var segment_length := 2.0 * radius * sin(PI / float(segments)) * 1.08
    var depth := TARGET_BOARD_THICKNESS * 1.08
    var center_depth := -TARGET_BOARD_THICKNESS * 0.5

    for index in range(segments):
        var angle := TAU * float(index) / float(segments)
        var radial := TARGET_RIGHT * cos(angle) + TARGET_V * sin(angle)
        var tangent := -TARGET_RIGHT * sin(angle) + TARGET_V * cos(angle)
        var position := _target_point(u, v, center_depth) + radial * radius
        var basis := Basis(tangent, TARGET_N, radial).orthonormalized()
        _add_oriented_static_box(
            "WhiteHole_%d_%02d" % [points, index],
            Vector3(segment_length, depth, HOLE_WALL_THICKNESS),
            position,
            basis,
            hole_material,
            target_physics_material
        )

func _add_hole_void(u: float, v: float, points: int) -> void:
    var disk := MeshInstance3D.new()
    disk.name = "HoleVoid_%d" % points
    disk.position = _target_point(u, v, -TARGET_BOARD_THICKNESS - 0.018)
    disk.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()

    var mesh := CylinderMesh.new()
    mesh.top_radius = TARGET_HOLE_RADIUS * 0.97
    mesh.bottom_radius = TARGET_HOLE_RADIUS * 0.97
    mesh.height = 0.004
    mesh.radial_segments = 32
    mesh.material = hole_void_material
    disk.mesh = mesh
    add_child(disk)

func _add_hole_label(u: float, v: float, points: int) -> void:
    var label := Label3D.new()
    label.name = "HoleLabel_%d" % points
    label.text = str(points)
    label.font_size = 54 if points < 100 else 46
    label.pixel_size = 0.0015
    label.modulate = Color(0.93, 0.92, 0.88)
    label.outline_size = 4
    label.outline_modulate = Color(0.08, 0.05, 0.04)
    label.position = _target_point(u, maxf(0.025, v - TARGET_HOLE_RADIUS * 1.45), 0.003)
    label.basis = Basis(TARGET_RIGHT, TARGET_V, TARGET_N).orthonormalized()
    add_child(label)

func _add_score_reset_point(points: int, u: float, v: float) -> void:
    var area := Area3D.new()
    area.name = "ScoreReset_%d" % points
    area.position = _target_point(u, v, -0.004)
    area.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    area.collision_layer = 0
    area.collision_mask = 1
    area.monitoring = true
    add_child(area)

    var collision := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = TARGET_HOLE_RADIUS * 0.94
    shape.height = 0.018
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_score_reset_entered.bind(points))

func _on_score_reset_entered(body: Node3D, points: int) -> void:
    if not (body is SkeeBallBall):
        return

    var ball := body as SkeeBallBall
    if ball.scored or not ball.launched:
        return

    ball.mark_scored()
    scored.emit(points, ball)

func _build_backboard() -> void:
    var marquee_center_y := 1.82
    _add_static_box("Backboard", Vector3(TARGET_WIDTH, 0.48, 0.055), Vector3(0.0, 1.60, BACK_Z + 0.060), blue_material)
    _add_visual_box("Marquee", Vector3(ALLEY_WIDTH - 0.055, 0.42, 0.065), Vector3(0.0, marquee_center_y, BACK_Z + 0.078), blue_material)
    _add_visual_box("MarqueeTopTrim", Vector3(ALLEY_WIDTH - 0.035, 0.040, 0.075), Vector3(0.0, marquee_center_y + 0.23, BACK_Z + 0.085), gold_material)

    var title := Label3D.new()
    title.text = "SLOT BALL"
    title.font_size = 96
    title.pixel_size = 0.0022
    title.modulate = Color(0.95, 0.72, 0.16)
    title.outline_size = 10
    title.outline_modulate = Color(0.32, 0.055, 0.035)
    title.position = Vector3(0.0, marquee_center_y, BACK_Z + 0.118)
    add_child(title)

func _build_invisible_containment() -> void:
    var head_front_z := ALLEY_REAR_Z + 0.14
    var head_depth := head_front_z - BACK_Z
    var head_center_z := (head_front_z + BACK_Z) * 0.5

    _add_invisible_static_box("InvisibleTargetCeiling", Vector3(ALLEY_WIDTH - 0.06, 0.05, head_depth), Vector3(0.0, 2.05, head_center_z))

    var side_x := ALLEY_WIDTH * 0.5 - 0.075
    for side in [-1.0, 1.0]:
        _add_invisible_static_box(
            "InvisibleTargetSide_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.025, 1.55, head_depth),
            Vector3(side * side_x, 1.28, head_center_z)
        )

func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    surface.add_vertex(a)
    surface.add_vertex(b)
    surface.add_vertex(c)
    surface.add_vertex(a)
    surface.add_vertex(c)
    surface.add_vertex(d)

func _add_static_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    material: Material,
    rotation_value: Vector3 = Vector3.ZERO,
    physics_material: PhysicsMaterial = null
) -> StaticBody3D:
    return _add_oriented_static_box(
        node_name,
        size,
        position,
        Basis.from_euler(rotation_value),
        material,
        physics_material
    )

func _add_oriented_static_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    basis: Basis,
    material: Material,
    physics_material: PhysicsMaterial = null
) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = position
    body.basis = basis
    body.collision_layer = 1
    body.collision_mask = 1
    if physics_material != null:
        body.physics_material_override = physics_material
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

func _add_invisible_static_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    rotation_value: Vector3 = Vector3.ZERO
) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = position
    body.rotation = rotation_value
    body.collision_layer = 1
    body.collision_mask = 1
    body.physics_material_override = target_physics_material
    add_child(body)

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
    return _add_oriented_visual_box(
        node_name,
        size,
        position,
        Basis.from_euler(rotation_value),
        material
    )

func _add_oriented_visual_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    basis: Basis,
    material: Material
) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = node_name
    mesh_instance.position = position
    mesh_instance.basis = basis

    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    mesh_instance.mesh = mesh
    add_child(mesh_instance)
    return mesh_instance
