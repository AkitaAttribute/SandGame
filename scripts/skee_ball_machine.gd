class_name SkeeBallMachine
extends Node3D

signal scored(points: int, ball: SkeeBallBall)

# Full-size classic alley dimensions. One Godot unit = one metre.
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
const CHUTE_HEIGHT := 4.0 * INCH
const CHUTE_THICKNESS := 0.25 * INCH
const LANE_SLOPE := deg_to_rad(4.0)
const TARGET_ANGLE := deg_to_rad(50.0)

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

# Measured target-board hole layout. Values are hole centers measured from
# the lower edge of the 38-inch target board. Every black scoring hole is 4".
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
var metal_material: StandardMaterial3D
var rubber_material: StandardMaterial3D
var net_material: StandardMaterial3D

func _ready() -> void:
    _build_materials()
    _build_alley_cabinet()
    _build_lane_and_ball_hop()
    _build_playfield_cabinet()
    _build_target_board()
    _build_score_guides()
    _build_backboard_and_cage()

func ball_start_transform() -> Transform3D:
    var z := BALL_START_LOCAL.z
    var y := _straight_lane_y(z) + SkeeBallBall.RADIUS + 0.004
    return Transform3D(Basis.IDENTITY, to_global(Vector3(0.0, y, z)))

func _build_materials() -> void:
    cabinet_material = _material(Color(0.32, 0.060, 0.038), 0.70)
    blue_material = _material(Color(0.070, 0.19, 0.29), 0.68)
    gold_material = _material(Color(0.78, 0.47, 0.07), 0.46, 0.10)
    cork_material = _material(Color(0.39, 0.45, 0.30), 0.92)
    target_material = _material(Color(0.56, 0.105, 0.075), 0.84)
    metal_material = _material(Color(0.77, 0.76, 0.70), 0.40, 0.15)
    rubber_material = _material(Color(0.025, 0.026, 0.027), 0.94)
    net_material = _material(Color(0.44, 0.49, 0.50), 0.63, 0.08)

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

    _add_static_box(
        "AlleyLeftSide",
        Vector3(side_thickness, ALLEY_HEIGHT, panel_length),
        Vector3(-side_x, ALLEY_HEIGHT * 0.5, center_z),
        cabinet_material
    )
    _add_static_box(
        "AlleyRightSide",
        Vector3(side_thickness, ALLEY_HEIGHT, panel_length),
        Vector3(side_x, ALLEY_HEIGHT * 0.5, center_z),
        cabinet_material
    )

    # The commercial cabinet has an angled/short front face; keep the collision
    # simple while matching the real 29-30 inch footprint.
    _add_static_box(
        "FrontFace",
        Vector3(ALLEY_WIDTH, 0.42, 0.075),
        Vector3(0.0, 0.21, FRONT_Z - 0.035),
        cabinet_material
    )
    _add_visual_box(
        "FrontInset",
        Vector3(ALLEY_WIDTH - 0.18, 0.30, 0.012),
        Vector3(0.0, 0.23, FRONT_Z - 0.078),
        blue_material
    )

    # Thin channel covers along the outer edges of the lane.
    var straight_len := LANE_FRONT_Z - HOP_START_Z
    var center_lane_z := (LANE_FRONT_Z + HOP_START_Z) * 0.5
    var center_lane_y := (_straight_lane_y(LANE_FRONT_Z) + _straight_lane_y(HOP_START_Z)) * 0.5
    var rail_x := ROLLING_WIDTH * 0.5 + 0.030
    for side in [-1.0, 1.0]:
        _add_static_box(
            "GoldChannel_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.050, 0.035, straight_len),
            Vector3(side * rail_x, center_lane_y + 0.040, center_lane_z),
            gold_material,
            Vector3(LANE_SLOPE, 0.0, 0.0)
        )

func _straight_lane_y(z: float) -> float:
    return LANE_FRONT_Y + (LANE_FRONT_Z - z) * tan(LANE_SLOPE)

func _build_lane_and_ball_hop() -> void:
    var profile: Array[Vector2] = []
    profile.append(Vector2(LANE_FRONT_Z, _straight_lane_y(LANE_FRONT_Z)))
    profile.append(Vector2(0.90, _straight_lane_y(0.90)))
    profile.append(Vector2(0.30, _straight_lane_y(0.30)))
    profile.append(Vector2(HOP_START_Z, _straight_lane_y(HOP_START_Z)))

    var hop_y := _straight_lane_y(HOP_START_Z)
    profile.append(Vector2(HOP_START_Z - 0.070, hop_y + 0.006))
    profile.append(Vector2(HOP_START_Z - 0.135, hop_y + 0.021))
    profile.append(Vector2(HOP_START_Z - 0.195, hop_y + 0.047))
    profile.append(Vector2(HOP_START_Z - 0.245, hop_y + 0.082))
    profile.append(Vector2(HOP_END_Z, hop_y + 0.126))

    var half_width := ROLLING_WIDTH * 0.5
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(cork_material)

    for index in range(profile.size() - 1):
        var a := profile[index]
        var b := profile[index + 1]
        var left_a := Vector3(-half_width, a.y, a.x)
        var right_a := Vector3(half_width, a.y, a.x)
        var left_b := Vector3(-half_width, b.y, b.x)
        var right_b := Vector3(half_width, b.y, b.x)
        _add_quad(surface, left_a, right_a, right_b, left_b)

    surface.generate_normals()
    var lane_mesh := surface.commit()
    var lane_instance := MeshInstance3D.new()
    lane_instance.name = "MeasuredCorkLane"
    lane_instance.mesh = lane_mesh
    add_child(lane_instance)

    var lane_body := StaticBody3D.new()
    lane_body.name = "LaneCollision"
    lane_body.collision_layer = 1
    lane_body.collision_mask = 1
    add_child(lane_body)
    var lane_collision := CollisionShape3D.new()
    lane_collision.shape = lane_mesh.create_trimesh_shape()
    lane_body.add_child(lane_collision)

    # 18 1/4" measured clear distance between the hard-rubber bumpers.
    var bumper_thickness := 0.025
    var bumper_x := BUMPER_GAP * 0.5 + bumper_thickness * 0.5
    var bumper_len := LANE_FRONT_Z - HOP_START_Z
    var bumper_z := (LANE_FRONT_Z + HOP_START_Z) * 0.5
    var bumper_y := (_straight_lane_y(LANE_FRONT_Z) + _straight_lane_y(HOP_START_Z)) * 0.5 + 0.032
    for side in [-1.0, 1.0]:
        _add_static_box(
            "HardRubberBumper_%s" % ("L" if side < 0.0 else "R"),
            Vector3(bumper_thickness, 0.050, bumper_len),
            Vector3(side * bumper_x, bumper_y, bumper_z),
            rubber_material,
            Vector3(LANE_SLOPE, 0.0, 0.0)
        )

func _build_playfield_cabinet() -> void:
    var head_front_z := ALLEY_REAR_Z + 0.10
    var head_depth := PLAYFIELD_DEPTH
    var head_center_z := head_front_z - head_depth * 0.5
    var side_thickness := 0.055
    var side_x := ALLEY_WIDTH * 0.5 - side_thickness * 0.5

    _add_static_box(
        "HeadLeftSide",
        Vector3(side_thickness, OVERALL_HEIGHT, head_depth),
        Vector3(-side_x, OVERALL_HEIGHT * 0.5, head_center_z),
        cabinet_material
    )
    _add_static_box(
        "HeadRightSide",
        Vector3(side_thickness, OVERALL_HEIGHT, head_depth),
        Vector3(side_x, OVERALL_HEIGHT * 0.5, head_center_z),
        cabinet_material
    )
    _add_static_box(
        "HeadBack",
        Vector3(ALLEY_WIDTH, OVERALL_HEIGHT, 0.050),
        Vector3(0.0, OVERALL_HEIGHT * 0.5, BACK_Z + 0.025),
        cabinet_material
    )

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
    # Dense grid with triangles omitted inside the measured 4" scoring holes.
    # This gives the physical ball actual openings rather than invisible scores.
    var columns := 56
    var rows := 76
    var du := TARGET_WIDTH / float(columns)
    var dv := TARGET_LENGTH / float(rows)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(target_material)
    var holes := _target_holes()

    for row in range(rows):
        var v0 := float(row) * dv
        var v1 := float(row + 1) * dv
        for column in range(columns):
            var u0 := -TARGET_WIDTH * 0.5 + float(column) * du
            var u1 := u0 + du
            var center_u := (u0 + u1) * 0.5
            var center_v := (v0 + v1) * 0.5
            if _inside_target_hole(center_u, center_v, holes, TARGET_HOLE_RADIUS + maxf(du, dv) * 0.45):
                continue

            var a := _target_point(u0, v0)
            var b := _target_point(u1, v0)
            var c := _target_point(u1, v1)
            var d := _target_point(u0, v1)
            _add_quad(surface, a, b, c, d)

    surface.generate_normals()
    var board_mesh := surface.commit()
    var board_instance := MeshInstance3D.new()
    board_instance.name = "MeasuredTargetBoard"
    board_instance.mesh = board_mesh
    add_child(board_instance)

    var board_body := StaticBody3D.new()
    board_body.name = "TargetBoardCollision"
    board_body.collision_layer = 1
    board_body.collision_mask = 1
    add_child(board_body)
    var board_collision := CollisionShape3D.new()
    board_collision.shape = board_mesh.create_trimesh_shape()
    board_body.add_child(board_collision)

    # Catch/score volumes sit just behind each physical hole.
    for hole in holes:
        _add_score_hole(int(hole["points"]), float(hole["u"]), float(hole["v"]))

func _inside_target_hole(u: float, v: float, holes: Array[Dictionary], radius: float) -> bool:
    for hole in holes:
        var du := u - float(hole["u"])
        var dv := v - float(hole["v"])
        if du * du + dv * dv <= radius * radius:
            return true
    return false

func _add_score_hole(points: int, u: float, v: float) -> void:
    var area := Area3D.new()
    area.name = "ScoreHole_%d" % points
    area.position = _target_point(u, v, -0.045)
    area.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V)
    area.collision_layer = 0
    area.collision_mask = 1
    area.monitoring = true
    add_child(area)

    var collision := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = TARGET_HOLE_RADIUS * 1.08
    shape.height = 0.11
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_score_hole_entered.bind(points))

func _on_score_hole_entered(body: Node3D, points: int) -> void:
    if not (body is SkeeBallBall):
        return
    var ball := body as SkeeBallBall
    if ball.scored or not ball.launched:
        return
    ball.mark_scored()
    scored.emit(points, ball)

func _build_score_guides() -> void:
    # 4"-tall, 1/4"-thick chute material is taken directly from the measured
    # commercial target. The large 10/20 guide radii follow the classic layout;
    # the individual higher-value chutes surround their measured 4" holes.
    _add_guide_ring("Guide10", 0.0, 0.285, 0.282, 32, 10)
    _add_guide_ring("Guide20", 0.0, 0.360, 0.178, 26, 20)
    _add_chute_ring(0.0, V30, 30)
    _add_chute_ring(0.0, V40, 40)
    _add_chute_ring(0.0, V50, 50)
    _add_chute_ring(-HUNDO_X, V100, 100)
    _add_chute_ring(HUNDO_X, V100, 100)

    # Small measured-machine-style bumpers reduce direct flyovers into the
    # lower 10/20 return holes.
    for item in [
        Vector2(-0.155, V10 + 0.030), Vector2(0.155, V10 + 0.030),
        Vector2(-0.125, V20 + 0.020), Vector2(0.125, V20 + 0.020),
    ]:
        _add_target_bumper(item.x, item.y)

func _add_chute_ring(u: float, v: float, points: int) -> void:
    _add_guide_ring("Chute%d" % points, u, v, TARGET_HOLE_RADIUS + 0.014, 18, points)

func _add_guide_ring(node_name: String, u: float, v: float, radius: float, segments: int, points: int) -> void:
    var segment_length := 2.0 * radius * sin(PI / float(segments)) * 1.08
    for index in range(segments):
        var angle := TAU * float(index) / float(segments)
        var radial := TARGET_RIGHT * cos(angle) + TARGET_V * sin(angle)
        var tangent := -TARGET_RIGHT * sin(angle) + TARGET_V * cos(angle)
        var position := _target_point(u, v) + radial * radius + TARGET_N * (CHUTE_HEIGHT * 0.5)
        var basis := Basis(tangent, TARGET_N, radial).orthonormalized()
        _add_oriented_static_box(
            "%s_%02d" % [node_name, index],
            Vector3(segment_length, CHUTE_HEIGHT, CHUTE_THICKNESS),
            position,
            basis,
            metal_material
        )

    var label := Label3D.new()
    label.name = "%s_Label" % node_name
    label.text = str(points)
    label.font_size = 42 if points < 100 else 34
    label.modulate = Color(0.10, 0.08, 0.065)
    label.outline_size = 3
    label.outline_modulate = Color(0.90, 0.87, 0.77)
    label.position = _target_point(u, maxf(0.025, v - radius * 0.62), CHUTE_HEIGHT + 0.012)
    label.basis = Basis(TARGET_RIGHT, TARGET_V, TARGET_N).orthonormalized()
    add_child(label)

func _add_target_bumper(u: float, v: float) -> void:
    var cylinder := StaticBody3D.new()
    cylinder.name = "TargetBumper"
    cylinder.position = _target_point(u, v, 0.018)
    cylinder.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V)
    cylinder.collision_layer = 1
    cylinder.collision_mask = 1
    add_child(cylinder)

    var mesh_instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.014
    mesh.bottom_radius = 0.014
    mesh.height = 0.036
    mesh.radial_segments = 10
    mesh.material = rubber_material
    mesh_instance.mesh = mesh
    cylinder.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = 0.014
    shape.height = 0.036
    collision.shape = shape
    cylinder.add_child(collision)

func _build_backboard_and_cage() -> void:
    var target_top := _target_point(0.0, TARGET_LENGTH)
    var marquee_center_y := 1.82
    _add_static_box(
        "Backboard",
        Vector3(TARGET_WIDTH, 0.48, 0.035),
        Vector3(0.0, 1.60, BACK_Z + 0.060),
        blue_material
    )
    _add_visual_box(
        "Marquee",
        Vector3(ALLEY_WIDTH - 0.055, 0.42, 0.055),
        Vector3(0.0, marquee_center_y, BACK_Z + 0.078),
        blue_material
    )
    _add_visual_box(
        "MarqueeTopTrim",
        Vector3(ALLEY_WIDTH - 0.035, 0.040, 0.070),
        Vector3(0.0, marquee_center_y + 0.23, BACK_Z + 0.085),
        gold_material
    )

    var title := Label3D.new()
    title.text = "SLOT BALL"
    title.font_size = 76
    title.modulate = Color(0.95, 0.72, 0.16)
    title.outline_size = 11
    title.outline_modulate = Color(0.32, 0.055, 0.035)
    title.position = Vector3(0.0, marquee_center_y, BACK_Z + 0.115)
    add_child(title)

    # Cage follows the measured 29" cabinet rather than the oversized first pass.
    var cage_x := ALLEY_WIDTH * 0.5 - 0.045
    var cage_bottom := TARGET_BOTTOM + TARGET_N * 0.03
    var cage_top := target_top + TARGET_N * 0.03
    var side_center := (cage_bottom + cage_top) * 0.5
    var side_length := cage_bottom.distance_to(cage_top)
    var side_basis := Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()

    for side in [-1.0, 1.0]:
        _add_oriented_visual_box(
            "CageSide_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.035, 0.035, side_length),
            side_center + TARGET_RIGHT * side * cage_x,
            side_basis,
            gold_material
        )

    # A light net grid across the face, primarily visual; the cabinet/room catch
    # obvious misses while keeping the target readable.
    for x_index in range(-4, 5):
        var x := float(x_index) * (TARGET_WIDTH / 9.0)
        _add_oriented_visual_box(
            "NetV_%d" % x_index,
            Vector3(0.012, 0.012, TARGET_LENGTH),
            _target_point(x, TARGET_LENGTH * 0.5, 0.18),
            side_basis,
            net_material
        )
    for row in range(9):
        var v := (float(row) + 0.5) * TARGET_LENGTH / 9.0
        _add_oriented_visual_box(
            "NetH_%d" % row,
            Vector3(TARGET_WIDTH, 0.012, 0.012),
            _target_point(0.0, v, 0.18),
            side_basis,
            net_material
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
    rotation_value: Vector3 = Vector3.ZERO
) -> StaticBody3D:
    var basis := Basis.from_euler(rotation_value)
    return _add_oriented_static_box(node_name, size, position, basis, material)

func _add_oriented_static_box(
    node_name: String,
    size: Vector3,
    position: Vector3,
    basis: Basis,
    material: Material
) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = position
    body.basis = basis
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
    return _add_oriented_visual_box(node_name, size, position, Basis.from_euler(rotation_value), material)

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
