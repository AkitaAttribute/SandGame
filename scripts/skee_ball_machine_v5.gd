class_name SkeeBallMachineV5
extends SkeeBallMachine

# Mechanism rebuilt from the user-supplied tabletop STL package.
# The STL files are measurement references only; no STL is imported at runtime.
const MODEL_SCALE := (3.0 * 0.0254) / 19.0

const MODEL_FACE_BOTTOM_Y := -96.7106781
const MODEL_FACE_BOTTOM_Z := -0.7106781

const FACE_BOTTOM := Vector3(0.0, 0.6400, -0.7000)
const FACE_V := Vector3(0.0, 0.70710678, -0.70710678)
const FACE_N := Vector3(0.0, 0.70710678, 0.70710678)
const FACE_RIGHT := Vector3.RIGHT

const FACE_WIDTH := 154.0 * MODEL_SCALE
const FACE_LENGTH := 200.0 * MODEL_SCALE
const CABINET_WIDTH := 160.0 * MODEL_SCALE
const BOARD_THICKNESS := 10.0 * MODEL_SCALE

const BALL_MODEL_DIAMETER := 19.0
const HOLE_RADIUS := 12.5 * MODEL_SCALE
const HOLE_CUT_RADIUS := 13.0 * MODEL_SCALE
const HOLE_LINER_WIDTH := 0.5 * MODEL_SCALE

const GUIDE_HEIGHT := 30.0 * MODEL_SCALE
const GUIDE_WALL := 1.75 * MODEL_SCALE
const U_WALL := 1.1421 * MODEL_SCALE
const RING_LIFT := 0.15 * MODEL_SCALE
const SEGMENTS := 128

# Target geometry measured from skeeball-face.stl in its own face coordinates.
const H10 := 41.0 * MODEL_SCALE
const H20 := 71.0 * MODEL_SCALE
const H30 := 99.0 * MODEL_SCALE
const H40 := 142.0 * MODEL_SCALE
const H50 := 177.0 * MODEL_SCALE
const H100 := 182.0 * MODEL_SCALE
const X100 := 55.0 * MODEL_SCALE

const U_CENTER := 100.9973 * MODEL_SCALE
const U_RADIUS := 74.4333 * MODEL_SCALE
const U_TOP := 191.0 * MODEL_SCALE

const C20 := 108.9973 * MODEL_SCALE
const R20 := 51.875 * MODEL_SCALE
const C30 := 105.4973 * MODEL_SCALE
const R30 := 20.125 * MODEL_SCALE
const C40 := 143.4973 * MODEL_SCALE
const R40 := 15.375 * MODEL_SCALE
const C50 := 177.9973 * MODEL_SCALE
const R50 := 14.875 * MODEL_SCALE
const C100 := 181.9973 * MODEL_SCALE
const R100 := 13.875 * MODEL_SCALE

# Shared STL coordinate relationship between lane, kicker and scoring face.
# The target backing starts almost directly behind the kicker, but is lower.
const MODEL_LANE_Z := 6.0
const MODEL_LANE_FLAT_END_Y := -152.25
const MODEL_LANE_UNDER_END_Y := -101.0
const MODEL_LANE_UNDER_END_Z := -0.25
const MODEL_KICKER_START_Y := -148.242527
const MODEL_KICKER_START_Z := 5.511284
const MODEL_KICKER_END_Y := -97.339554
const MODEL_KICKER_END_Z := 12.427876

const LANE_WIDTH := 160.0 * MODEL_SCALE
const KICKER_WIDTH := 130.0 * MODEL_SCALE
const LANE_THICKNESS := 9.0 * MODEL_SCALE
const START_Z := 1.30

const REAR_DROP_DEPTH := 35.0 * MODEL_SCALE


func _build_materials() -> void:
    super._build_materials()
    target_material.albedo_color = Color(0.18, 0.070, 0.040)
    target_material.roughness = 0.97
    target_material.metallic = 0.0

    hole_material.albedo_color = Color(0.94, 0.93, 0.89)
    hole_material.roughness = 0.90
    hole_material.metallic = 0.0

    cork_material.albedo_color = Color(0.43, 0.47, 0.28)
    cork_material.roughness = 0.94

    lane_physics_material.friction = 0.88
    lane_physics_material.bounce = 0.015
    target_physics_material.friction = 0.80
    target_physics_material.bounce = 0.025


func _model_y_to_local_z(model_y: float) -> float:
    return FACE_BOTTOM.z - (model_y - MODEL_FACE_BOTTOM_Y) * MODEL_SCALE


func _model_z_to_local_y(model_z: float) -> float:
    return FACE_BOTTOM.y + (model_z - MODEL_FACE_BOTTOM_Z) * MODEL_SCALE


func _target_point(u: float, v: float, normal_offset: float = 0.0) -> Vector3:
    return FACE_BOTTOM + FACE_RIGHT * u + FACE_V * v + FACE_N * normal_offset


func _lane_y() -> float:
    return _model_z_to_local_y(MODEL_LANE_Z)


func ball_start_transform() -> Transform3D:
    var local_position := Vector3(
        0.0,
        _lane_y() + SkeeBallBall.BASE_RADIUS + 0.004,
        START_Z
    )
    return Transform3D(Basis.IDENTITY, to_global(local_position))


func _build_alley_cabinet() -> void:
    var side_thickness := 0.040
    var front_z := FRONT_Z
    var back_z := FACE_BOTTOM.z + 0.04
    var length := front_z - back_z
    var center_z := (front_z + back_z) * 0.5
    var side_x := CABINET_WIDTH * 0.5 + side_thickness * 0.5

    _add_static_box(
        "AlleyLeftSide",
        Vector3(side_thickness, ALLEY_HEIGHT, length),
        Vector3(-side_x, ALLEY_HEIGHT * 0.5, center_z),
        cabinet_material
    )
    _add_static_box(
        "AlleyRightSide",
        Vector3(side_thickness, ALLEY_HEIGHT, length),
        Vector3(side_x, ALLEY_HEIGHT * 0.5, center_z),
        cabinet_material
    )

    _add_static_box(
        "FrontFace",
        Vector3(CABINET_WIDTH + side_thickness * 2.0, 0.42, 0.075),
        Vector3(0.0, 0.21, front_z - 0.035),
        cabinet_material
    )
    _add_visual_box(
        "FrontInset",
        Vector3(CABINET_WIDTH - 0.11, 0.30, 0.012),
        Vector3(0.0, 0.23, front_z - 0.078),
        blue_material
    )

    var rail_height := 0.065
    var rail_width := 0.025
    var rail_z_front := front_z - 0.12
    var rail_z_back := _model_y_to_local_z(MODEL_LANE_FLAT_END_Y)
    var rail_length := rail_z_front - rail_z_back
    var rail_center_z := (rail_z_front + rail_z_back) * 0.5
    var rail_x := LANE_WIDTH * 0.5 - rail_width * 0.5
    for side in [-1.0, 1.0]:
        _add_static_box(
            "LaneRail_%s" % ("L" if side < 0.0 else "R"),
            Vector3(rail_width, rail_height, rail_length),
            Vector3(
                side * rail_x,
                _lane_y() + rail_height * 0.5,
                rail_center_z
            ),
            rubber_material,
            Vector3.ZERO,
            lane_physics_material
        )


func _build_lane_and_ball_hop() -> void:
    # Full-width under-lane from the player's end through the kicker area.
    # These coordinates reproduce skeeball-lane1/lane2 from the supplied model.
    var under_profile: Array[Vector2] = [
        Vector2(FRONT_Z - 0.08, _lane_y()),
        Vector2(_model_y_to_local_z(-501.0), _lane_y()),
        Vector2(_model_y_to_local_z(-301.0), _lane_y()),
        Vector2(_model_y_to_local_z(MODEL_LANE_FLAT_END_Y), _lane_y()),
        Vector2(
            _model_y_to_local_z(MODEL_LANE_UNDER_END_Y),
            _model_z_to_local_y(MODEL_LANE_UNDER_END_Z)
        ),
    ]
    _add_profile_surface(
        "RollingLane",
        LANE_WIDTH,
        under_profile,
        LANE_THICKNESS,
        cork_material,
        lane_physics_material
    )

    # The actual kicker profile is sampled from skeeball-ramp001.stl. It rises
    # out of the under-lane and finishes 13.14 model-mm above the face bottom.
    var kicker_profile := _kicker_profile()
    _add_profile_surface(
        "KickerRamp",
        KICKER_WIDTH,
        kicker_profile,
        LANE_THICKNESS,
        cork_material,
        lane_physics_material
    )

    # Low side guides stop the ball falling off the rolling lane while leaving
    # the center kicker and target transition unobstructed.
    var guide_width := 0.020
    var guide_height := 0.050
    var guide_start := FRONT_Z - 0.10
    var guide_end := _model_y_to_local_z(MODEL_KICKER_START_Y)
    var guide_length := guide_start - guide_end
    var guide_center := (guide_start + guide_end) * 0.5
    for side in [-1.0, 1.0]:
        _add_static_box(
            "RollingGuide_%s" % ("L" if side < 0.0 else "R"),
            Vector3(guide_width, guide_height, guide_length),
            Vector3(
                side * (LANE_WIDTH * 0.5 - guide_width * 0.5),
                _lane_y() + guide_height * 0.5,
                guide_center
            ),
            rubber_material,
            Vector3.ZERO,
            lane_physics_material
        )


func _kicker_profile() -> Array[Vector2]:
    var raw: Array[Vector2] = [
        Vector2(-148.242527, 5.511284),
        Vector2(-147.6181, 6.1852),
        Vector2(-147.1461, 6.6640),
        Vector2(-146.6664, 7.1225),
        Vector2(-146.1784, 7.5591),
        Vector2(-145.6812, 7.9724),
        Vector2(-145.1741, 8.3608),
        Vector2(-144.6560, 8.7230),
        Vector2(-144.1236, 9.0598),
        Vector2(-143.5727, 9.3726),
        Vector2(-142.9988, 9.6628),
        Vector2(-142.3977, 9.9319),
        Vector2(-141.7130, 10.2006),
        Vector2(-141.1180, 10.4059),
        Vector2(-140.2750, 10.6592),
        Vector2(-139.1790, 10.9358),
        Vector2(-137.5544, 11.2647),
        Vector2(-134.7459, 11.6884),
        Vector2(-127.3396, 12.4279),
        Vector2(-97.339554, 12.427876),
    ]

    var mapped: Array[Vector2] = []
    for point in raw:
        mapped.append(Vector2(
            _model_y_to_local_z(point.x),
            _model_z_to_local_y(point.y)
        ))
    return mapped


func _add_profile_surface(
    node_name: String,
    width: float,
    profile: Array[Vector2],
    thickness: float,
    material: Material,
    physics_material: PhysicsMaterial
) -> void:
    if profile.size() < 2:
        return

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(material)

    var half_width := width * 0.5
    for index in range(profile.size() - 1):
        var a := profile[index]
        var b := profile[index + 1]

        var atl := Vector3(-half_width, a.y, a.x)
        var atr := Vector3(half_width, a.y, a.x)
        var btl := Vector3(-half_width, b.y, b.x)
        var btr := Vector3(half_width, b.y, b.x)

        var abl := atl + Vector3.DOWN * thickness
        var abr := atr + Vector3.DOWN * thickness
        var bbl := btl + Vector3.DOWN * thickness
        var bbr := btr + Vector3.DOWN * thickness

        _add_quad(surface, atl, btl, btr, atr)
        _add_quad(surface, abr, bbr, bbl, abl)
        _add_quad(surface, abl, bbl, btl, atl)
        _add_quad(surface, atr, btr, bbr, abr)

        if index == 0:
            _add_quad(surface, abl, atl, atr, abr)
        if index == profile.size() - 2:
            _add_quad(surface, bbl, bbr, btr, btl)

    surface.generate_normals()
    var mesh := surface.commit()

    var body := StaticBody3D.new()
    body.name = node_name
    body.collision_layer = 1
    body.collision_mask = 1
    body.physics_material_override = physics_material
    add_child(body)

    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    body.add_child(visual)

    var collision := CollisionShape3D.new()
    collision.shape = mesh.create_trimesh_shape()
    body.add_child(collision)


func _build_playfield_cabinet() -> void:
    var face_top := _target_point(0.0, FACE_LENGTH)
    var head_front_z := FACE_BOTTOM.z + 0.08
    var head_back_z := minf(BACK_Z, face_top.z - 0.28)
    var head_depth := head_front_z - head_back_z
    var head_center_z := (head_front_z + head_back_z) * 0.5
    var side_thickness := 0.045
    var side_x := CABINET_WIDTH * 0.5 + side_thickness * 0.5

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
        Vector3(CABINET_WIDTH + side_thickness * 2.0, OVERALL_HEIGHT, 0.050),
        Vector3(0.0, OVERALL_HEIGHT * 0.5, head_back_z),
        cabinet_material
    )

    var face_basis := Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    var rail_width := 0.024
    var rail_height := 0.052
    for side in [-1.0, 1.0]:
        _add_oriented_static_box(
            "TargetRail_%s" % ("L" if side < 0.0 else "R"),
            Vector3(rail_width, rail_height, FACE_LENGTH),
            _target_point(
                side * (FACE_WIDTH * 0.5 + rail_width * 0.35),
                FACE_LENGTH * 0.5,
                rail_height * 0.5
            ),
            face_basis,
            gold_material,
            target_physics_material
        )


func _targets() -> Array[Dictionary]:
    return [
        {"points": 10, "u": 0.0, "v": H10, "id": "10"},
        {"points": 20, "u": 0.0, "v": H20, "id": "20"},
        {"points": 30, "u": 0.0, "v": H30, "id": "30"},
        {"points": 40, "u": 0.0, "v": H40, "id": "40"},
        {"points": 50, "u": 0.0, "v": H50, "id": "50"},
        {"points": 100, "u": -X100, "v": H100, "id": "100L"},
        {"points": 100, "u": X100, "v": H100, "id": "100R"},
    ]


func _build_target_board() -> void:
    _build_perforated_board()
    _build_rear_drop_space()

    # Target walls use single continuous meshes with no coplanar bottom faces.
    # This removes the CSG overlap/seam artifacts from the earlier versions.
    _add_u_wall(
        "Target10U",
        U_CENTER,
        U_RADIUS,
        U_TOP,
        U_WALL,
        GUIDE_HEIGHT
    )
    _add_ring_wall("Target20", 0.0, C20, R20, GUIDE_WALL, GUIDE_HEIGHT)
    _add_ring_wall("Target30", 0.0, C30, R30, GUIDE_WALL, GUIDE_HEIGHT)
    _add_ring_wall("Target40", 0.0, C40, R40, GUIDE_WALL, GUIDE_HEIGHT)
    _add_ring_wall("Target50", 0.0, C50, R50, GUIDE_WALL, GUIDE_HEIGHT)
    _add_ring_wall("Target100L", -X100, C100, R100, GUIDE_WALL, GUIDE_HEIGHT)
    _add_ring_wall("Target100R", X100, C100, R100, GUIDE_WALL, GUIDE_HEIGHT)

    _add_target_label("Label10", 10, 0.0, U_CENTER - U_RADIUS)
    _add_target_label("Label20", 20, 0.0, C20 - R20)
    _add_target_label("Label30", 30, 0.0, C30 - R30)
    _add_target_label("Label40", 40, 0.0, C40 - R40)
    _add_target_label("Label50", 50, 0.0, C50 - R50)
    _add_target_label("Label100L", 100, -X100, C100 - R100)
    _add_target_label("Label100R", 100, X100, C100 - R100)

    for target in _targets():
        var u := float(target["u"])
        var v := float(target["v"])
        _add_hole_liner("HoleLiner_%s" % String(target["id"]), u, v)
        _add_score_sensor(int(target["points"]), u, v)

    _add_miss_reset_area()


func _build_perforated_board() -> void:
    var frame := Node3D.new()
    frame.name = "TargetBoardFrame"
    frame.position = _target_point(
        0.0,
        FACE_LENGTH * 0.5,
        -BOARD_THICKNESS * 0.5
    )
    frame.basis = Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    add_child(frame)

    var assembly := CSGCombiner3D.new()
    assembly.name = "SevenHoleTargetBoard"
    assembly.use_collision = true
    assembly.collision_layer = 1
    assembly.collision_mask = 1
    frame.add_child(assembly)

    var plate := CSGBox3D.new()
    plate.name = "TargetPlate"
    plate.size = Vector3(FACE_WIDTH, BOARD_THICKNESS, FACE_LENGTH)
    plate.material = target_material
    assembly.add_child(plate)

    for target in _targets():
        var cut := CSGCylinder3D.new()
        cut.name = "ScoreCut_%s" % String(target["id"])
        cut.radius = HOLE_CUT_RADIUS
        cut.height = BOARD_THICKNESS * 3.0
        cut.sides = SEGMENTS
        cut.smooth_faces = true
        cut.operation = CSGShape3D.OPERATION_SUBTRACTION
        cut.position = Vector3(
            float(target["u"]),
            0.0,
            float(target["v"]) - FACE_LENGTH * 0.5
        )
        assembly.add_child(cut)


func _build_rear_drop_space() -> void:
    var basis := Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    _add_oriented_visual_box(
        "RearDropBack",
        Vector3(FACE_WIDTH, 0.010, FACE_LENGTH),
        _target_point(0.0, FACE_LENGTH * 0.5, -REAR_DROP_DEPTH),
        basis,
        hole_void_material
    )


func _add_ring_wall(
    node_name: String,
    u: float,
    v: float,
    radius: float,
    width: float,
    height: float
) -> void:
    var outer_radius := radius + width * 0.5
    var inner_radius := radius - width * 0.5
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(hole_material)

    for index in range(SEGMENTS):
        var a0 := TAU * float(index) / float(SEGMENTS)
        var a1 := TAU * float(index + 1) / float(SEGMENTS)

        var bo0 := _target_point(
            u + cos(a0) * outer_radius,
            v + sin(a0) * outer_radius,
            RING_LIFT
        )
        var bo1 := _target_point(
            u + cos(a1) * outer_radius,
            v + sin(a1) * outer_radius,
            RING_LIFT
        )
        var bi0 := _target_point(
            u + cos(a0) * inner_radius,
            v + sin(a0) * inner_radius,
            RING_LIFT
        )
        var bi1 := _target_point(
            u + cos(a1) * inner_radius,
            v + sin(a1) * inner_radius,
            RING_LIFT
        )

        var to0 := bo0 + FACE_N * height
        var to1 := bo1 + FACE_N * height
        var ti0 := bi0 + FACE_N * height
        var ti1 := bi1 + FACE_N * height

        _add_quad(surface, bo0, bo1, to1, to0)
        _add_quad(surface, bi1, bi0, ti0, ti1)
        _add_quad(surface, to0, to1, ti1, ti0)

    _commit_target_wall(node_name, surface)


func _add_u_wall(
    node_name: String,
    center_v: float,
    radius: float,
    top_v: float,
    width: float,
    height: float
) -> void:
    var path: Array[Vector2] = [
        Vector2(-radius, top_v),
        Vector2(-radius, center_v),
    ]

    var half_segments := int(SEGMENTS / 2)
    for index in range(1, half_segments + 1):
        var angle := PI + PI * float(index) / float(half_segments)
        path.append(Vector2(
            cos(angle) * radius,
            center_v + sin(angle) * radius
        ))
    path.append(Vector2(radius, top_v))

    var left_points: Array[Vector2] = []
    var right_points: Array[Vector2] = []
    for index in range(path.size()):
        var tangent: Vector2
        if index == 0:
            tangent = path[1] - path[0]
        elif index == path.size() - 1:
            tangent = path[index] - path[index - 1]
        else:
            tangent = path[index + 1] - path[index - 1]
        tangent = tangent.normalized()

        var side := Vector2(-tangent.y, tangent.x) * (width * 0.5)
        left_points.append(path[index] + side)
        right_points.append(path[index] - side)

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(hole_material)

    for index in range(path.size() - 1):
        var lb0 := _target_point(
            left_points[index].x,
            left_points[index].y,
            RING_LIFT
        )
        var lb1 := _target_point(
            left_points[index + 1].x,
            left_points[index + 1].y,
            RING_LIFT
        )
        var rb0 := _target_point(
            right_points[index].x,
            right_points[index].y,
            RING_LIFT
        )
        var rb1 := _target_point(
            right_points[index + 1].x,
            right_points[index + 1].y,
            RING_LIFT
        )

        var lt0 := lb0 + FACE_N * height
        var lt1 := lb1 + FACE_N * height
        var rt0 := rb0 + FACE_N * height
        var rt1 := rb1 + FACE_N * height

        _add_quad(surface, lb0, lb1, lt1, lt0)
        _add_quad(surface, rb1, rb0, rt0, rt1)
        _add_quad(surface, lt0, lt1, rt1, rt0)

    # Close the two upper ends of the U.
    for index in [0, path.size() - 1]:
        var lb := _target_point(
            left_points[index].x,
            left_points[index].y,
            RING_LIFT
        )
        var rb := _target_point(
            right_points[index].x,
            right_points[index].y,
            RING_LIFT
        )
        _add_quad(
            surface,
            rb,
            lb,
            lb + FACE_N * height,
            rb + FACE_N * height
        )

    _commit_target_wall(node_name, surface)


func _commit_target_wall(node_name: String, surface: SurfaceTool) -> void:
    surface.generate_normals()
    var mesh := surface.commit()

    var body := StaticBody3D.new()
    body.name = node_name
    body.collision_layer = 1
    body.collision_mask = 1
    body.physics_material_override = target_physics_material
    add_child(body)

    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    body.add_child(visual)

    var collision := CollisionShape3D.new()
    collision.shape = mesh.create_trimesh_shape()
    body.add_child(collision)


func _add_hole_liner(node_name: String, u: float, v: float) -> void:
    # White cylindrical lining through the backing. The playable inner radius
    # remains exactly 12.5 model-mm, preserving the STL's 25:19 hole/ball ratio.
    var outer_radius := HOLE_CUT_RADIUS
    var inner_radius := HOLE_RADIUS
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(hole_material)

    for index in range(SEGMENTS):
        var a0 := TAU * float(index) / float(SEGMENTS)
        var a1 := TAU * float(index + 1) / float(SEGMENTS)

        var fo0 := _target_point(
            u + cos(a0) * outer_radius,
            v + sin(a0) * outer_radius,
            -0.0004
        )
        var fo1 := _target_point(
            u + cos(a1) * outer_radius,
            v + sin(a1) * outer_radius,
            -0.0004
        )
        var fi0 := _target_point(
            u + cos(a0) * inner_radius,
            v + sin(a0) * inner_radius,
            -0.0004
        )
        var fi1 := _target_point(
            u + cos(a1) * inner_radius,
            v + sin(a1) * inner_radius,
            -0.0004
        )

        var bo0 := fo0 - FACE_N * BOARD_THICKNESS
        var bo1 := fo1 - FACE_N * BOARD_THICKNESS
        var bi0 := fi0 - FACE_N * BOARD_THICKNESS
        var bi1 := fi1 - FACE_N * BOARD_THICKNESS

        _add_quad(surface, fi0, fi1, bi1, bi0)
        _add_quad(surface, bo0, bo1, fo1, fo0)

    _commit_target_wall(node_name, surface)


func _add_score_sensor(points: int, u: float, v: float) -> void:
    var area := Area3D.new()
    area.name = "ScoreReset_%d" % points
    area.position = _target_point(u, v, -0.010)
    area.basis = Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    area.collision_layer = 0
    area.collision_mask = 1
    area.monitoring = true
    add_child(area)

    var collision := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = HOLE_RADIUS * 0.94
    shape.height = 0.030
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_score_entered.bind(points))


func _on_score_entered(body: Node3D, points: int) -> void:
    if not (body is SkeeBallBall):
        return
    var scored_ball := body as SkeeBallBall
    if scored_ball.scored or not scored_ball.launched:
        return
    scored_ball.mark_scored()
    scored.emit(points, scored_ball)


func _add_miss_reset_area() -> void:
    # Catch balls that fail to reach/stay on the target deck without adding
    # visible geometry in the launch gap.
    var area := Area3D.new()
    area.name = "MissReturn"
    area.position = Vector3(
        0.0,
        FACE_BOTTOM.y - 0.16,
        FACE_BOTTOM.z - 0.02
    )
    area.collision_layer = 0
    area.collision_mask = 1
    area.monitoring = true
    add_child(area)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(
        CABINET_WIDTH,
        0.28,
        0.48
    )
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_miss_entered)


func _on_miss_entered(body: Node3D) -> void:
    if body is SkeeBallBall:
        var missed_ball := body as SkeeBallBall
        if missed_ball.launched and not missed_ball.scored:
            missed_ball.reset_to_start()


func _add_target_label(
    node_name: String,
    points: int,
    u: float,
    v: float
) -> void:
    var label := Label3D.new()
    label.name = node_name
    label.text = str(points)
    label.font_size = 50 if points < 100 else 42
    label.pixel_size = 0.00105
    label.modulate = Color(0.08, 0.055, 0.040)
    label.outline_size = 0
    label.position = _target_point(
        u,
        v,
        GUIDE_HEIGHT * 0.56 + RING_LIFT
    )
    label.basis = Basis(FACE_RIGHT, FACE_N, -FACE_V).orthonormalized()
    add_child(label)


func _build_backboard() -> void:
    var face_top := _target_point(0.0, FACE_LENGTH)
    var backboard_y := face_top.y + 0.27
    var backboard_z := face_top.z - 0.10

    _add_static_box(
        "Backboard",
        Vector3(CABINET_WIDTH, 0.50, 0.055),
        Vector3(0.0, backboard_y, backboard_z),
        blue_material
    )
    _add_visual_box(
        "Marquee",
        Vector3(CABINET_WIDTH, 0.42, 0.065),
        Vector3(0.0, backboard_y + 0.24, backboard_z + 0.018),
        blue_material
    )
    _add_visual_box(
        "MarqueeTopTrim",
        Vector3(CABINET_WIDTH, 0.040, 0.075),
        Vector3(0.0, backboard_y + 0.47, backboard_z + 0.025),
        gold_material
    )

    var title := Label3D.new()
    title.text = "SLOT BALL"
    title.font_size = 72
    title.pixel_size = 0.0018
    title.modulate = Color(0.95, 0.72, 0.16)
    title.outline_size = 6
    title.outline_modulate = Color(0.32, 0.055, 0.035)
    title.position = Vector3(
        0.0,
        backboard_y + 0.24,
        backboard_z + 0.058
    )
    add_child(title)


func _build_invisible_containment() -> void:
    # Collision-only containment around the single machine; nothing obscures
    # the score face.
    var face_top := _target_point(0.0, FACE_LENGTH)
    var center_z := (FACE_BOTTOM.z + face_top.z) * 0.5
    var depth := FACE_BOTTOM.z - face_top.z + 0.40
    var side_x := CABINET_WIDTH * 0.5 + 0.012

    for side in [-1.0, 1.0]:
        _add_invisible_static_box(
            "TargetContainment_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.020, 1.50, depth),
            Vector3(
                side * side_x,
                FACE_BOTTOM.y + 0.58,
                center_z
            )
        )

    _add_invisible_static_box(
        "TargetCeiling",
        Vector3(CABINET_WIDTH, 0.025, depth),
        Vector3(
            0.0,
            face_top.y + GUIDE_HEIGHT + 0.34,
            center_z
        )
    )
