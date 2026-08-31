class_name SkeeBallMachineV3
extends SkeeBallMachineV2

# Physics-first reconstruction of the single classic target shown in the
# supplied cabinet reference. All dimensions in this script are local machine
# dimensions; SkeeBallMachine applies the existing 4x presentation scale.
# The active ball is a 3-inch ball in these same local dimensions.
const FACE_WIDTH := 34.0 * INCH
const HEAD_WIDTH := 36.0 * INCH
const FACE_LENGTH := 38.0 * INCH
const FACE_BOARD_THICKNESS := 0.75 * INCH
const FACE_V := Vector3(0.0, 0.70710678, -0.70710678)
const FACE_N := Vector3(0.0, 0.70710678, 0.70710678)
const FACE_RIGHT := Vector3.RIGHT

# Keep an honest jump gap, but account for the fact that a 4-inch-tall target
# wall projects toward the kicker on the inclined playfield. The lower U does
# not begin until four inches up the face, so its leading edge stays clear.
const MISS_SLOT := 5.75 * INCH
const FACE_BOTTOM := Vector3(0.0, 0.6600, -0.77375)

# Playable opening is fractionally generous compared with the nominal 4-inch
# hole. A 3-inch ball therefore has 0.55 inches of radial clearance, which is
# enough to tolerate rigid-body contact without making the holes look oversized.
const PLAY_HOLE_RADIUS := 2.05 * INCH
const PLAY_HOLE_DIAMETER := PLAY_HOLE_RADIUS * 2.0
const BALL_DIAMETER := 3.0 * INCH

# Clean, non-intersecting target layout derived from the supplied reference.
# The U and large circle are capture guides; all seven scores still drain
# through true openings in the backing.
const U_CENTER_V := 14.75 * INCH
const U_RADIUS := 10.75 * INCH
const U_LEG_TOP_V := 31.0 * INCH
const BIG_CIRCLE_CENTER_V := 15.50 * INCH
const BIG_CIRCLE_RADIUS := 8.25 * INCH

const T10_V := 7.00 * INCH
const T20_V := 11.50 * INCH
const T30_V := 17.00 * INCH
const T40_V := 27.50 * INCH
const T50_V := 34.00 * INCH
const T100_V := 34.50 * INCH
const T100_X := 13.75 * INCH

const R30 := 3.25 * INCH
const R40 := 2.95 * INCH
const R50 := 2.65 * INCH
const R100 := 2.25 * INCH

const CIRCLE_SEGMENTS := 128
const RING_LIFT := 0.035 * INCH
const REAR_CAVITY_DEPTH := 6.0 * INCH
const LABEL_FACE_OFFSET := 0.030 * INCH

func _build_materials() -> void:
    super._build_materials()
    target_material.albedo_color = Color(0.18, 0.070, 0.040)
    target_material.roughness = 0.96
    target_material.metallic = 0.0
    hole_material.albedo_color = Color(0.94, 0.93, 0.89)
    hole_material.roughness = 0.78
    hole_material.metallic = 0.0
    target_physics_material.friction = 0.80
    target_physics_material.bounce = 0.025

func _target_point(u: float, v: float, normal_offset: float = 0.0) -> Vector3:
    return FACE_BOTTOM + FACE_RIGHT * u + FACE_V * v + FACE_N * normal_offset

func _all_score_targets() -> Array[Dictionary]:
    return [
        {"points": 10, "u": 0.0, "v": T10_V, "id": "10"},
        {"points": 20, "u": 0.0, "v": T20_V, "id": "20"},
        {"points": 30, "u": 0.0, "v": T30_V, "id": "30"},
        {"points": 40, "u": 0.0, "v": T40_V, "id": "40"},
        {"points": 50, "u": 0.0, "v": T50_V, "id": "50"},
        {"points": 100, "u": -T100_X, "v": T100_V, "id": "100L"},
        {"points": 100, "u": T100_X, "v": T100_V, "id": "100R"},
    ]

func _build_playfield_cabinet() -> void:
    var head_front_z := ALLEY_REAR_Z + 0.10
    var head_depth := PLAYFIELD_DEPTH
    var head_center_z := head_front_z - head_depth * 0.5
    var side_thickness := 0.055
    var side_x := HEAD_WIDTH * 0.5 - side_thickness * 0.5

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
        Vector3(HEAD_WIDTH, OVERALL_HEIGHT, 0.050),
        Vector3(0.0, OVERALL_HEIGHT * 0.5, BACK_Z + 0.025),
        cabinet_material
    )

    var face_basis := Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    for side in [-1.0, 1.0]:
        _add_oriented_static_box(
            "TargetGoldRail_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.045, 0.070, FACE_LENGTH),
            _target_point(side * (FACE_WIDTH * 0.5 + 0.030), FACE_LENGTH * 0.5, 0.035),
            face_basis,
            gold_material,
            target_physics_material
        )

func _build_target_board() -> void:
    _build_target_frame()
    _build_perforated_target_board()
    _build_rear_drop_cavity()

    # Outer 10 target: one clean U-shaped CSG body. Its side bypass lanes are
    # 6.125 inches wide before the frame, versus a 3-inch ball diameter.
    _add_csg_u_wall(
        "Target10U",
        U_CENTER_V,
        U_RADIUS,
        U_LEG_TOP_V,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS
    )
    _add_face_label("Target10Label", 10, 0.0, U_CENTER_V, U_RADIUS)

    # Large 20 capture ring. It is wholly nested inside the U and has no shared
    # or coplanar geometry with it.
    _add_csg_ring(
        "Target20Circle",
        0.0,
        BIG_CIRCLE_CENTER_V,
        BIG_CIRCLE_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS,
        RING_LIFT
    )
    _add_face_label("Target20Label", 20, 0.0, BIG_CIRCLE_CENTER_V, BIG_CIRCLE_RADIUS)

    _add_scoring_cup("Target30", 30, 0.0, T30_V, R30)
    _add_scoring_cup("Target40", 40, 0.0, T40_V, R40)
    _add_scoring_cup("Target50", 50, 0.0, T50_V, R50)
    _add_scoring_cup("Target100L", 100, -T100_X, T100_V, R100)
    _add_scoring_cup("Target100R", 100, T100_X, T100_V, R100)

    for target in _all_score_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var target_id := String(target["id"])
        _add_drain_throat("Drain_%s" % target_id, u, v)
        _add_score_reset_point(points, u, v)

func _add_scoring_cup(
    node_name: String,
    points: int,
    u: float,
    v: float,
    radius: float
) -> void:
    _add_csg_ring(
        node_name,
        u,
        v,
        radius,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS,
        RING_LIFT
    )
    _add_face_label("%sLabel" % node_name, points, u, v, radius)

func _build_target_frame() -> void:
    var basis := Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    var half_width := FACE_WIDTH * 0.5
    var rail_half := FRAME_RAIL_WIDTH * 0.5
    var depth_center := -FRAME_RAIL_DEPTH * 0.5

    _add_oriented_static_box(
        "TargetFrameLeft",
        Vector3(FRAME_RAIL_WIDTH, FRAME_RAIL_DEPTH, FACE_LENGTH + FRAME_RAIL_WIDTH * 2.0),
        _target_point(-half_width - rail_half, FACE_LENGTH * 0.5, depth_center),
        basis,
        cabinet_material,
        target_physics_material
    )
    _add_oriented_static_box(
        "TargetFrameRight",
        Vector3(FRAME_RAIL_WIDTH, FRAME_RAIL_DEPTH, FACE_LENGTH + FRAME_RAIL_WIDTH * 2.0),
        _target_point(half_width + rail_half, FACE_LENGTH * 0.5, depth_center),
        basis,
        cabinet_material,
        target_physics_material
    )
    _add_oriented_static_box(
        "TargetFrameBottom",
        Vector3(FACE_WIDTH, FRAME_RAIL_DEPTH, FRAME_RAIL_WIDTH),
        _target_point(0.0, -rail_half, depth_center),
        basis,
        cabinet_material,
        target_physics_material
    )
    _add_oriented_static_box(
        "TargetFrameTop",
        Vector3(FACE_WIDTH, FRAME_RAIL_DEPTH, FRAME_RAIL_WIDTH),
        _target_point(0.0, FACE_LENGTH + rail_half, depth_center),
        basis,
        cabinet_material,
        target_physics_material
    )

func _build_perforated_target_board() -> void:
    var frame := Node3D.new()
    frame.name = "PerforatedTargetBoardFrame"
    frame.position = _target_point(0.0, FACE_LENGTH * 0.5, -FACE_BOARD_THICKNESS * 0.5)
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
    plate.size = Vector3(FACE_WIDTH, FACE_BOARD_THICKNESS, FACE_LENGTH)
    plate.material = target_material
    assembly.add_child(plate)

    for target in _all_score_targets():
        var cut := CSGCylinder3D.new()
        cut.name = "ScoreCut_%s" % String(target["id"])
        cut.radius = PLAY_HOLE_RADIUS
        cut.height = FACE_BOARD_THICKNESS * 3.2
        cut.sides = CIRCLE_SEGMENTS
        cut.smooth_faces = true
        cut.operation = CSGShape3D.OPERATION_SUBTRACTION
        cut.position = Vector3(
            float(target["u"]),
            0.0,
            float(target["v"]) - FACE_LENGTH * 0.5
        )
        assembly.add_child(cut)

func _build_rear_drop_cavity() -> void:
    var basis := Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    var cavity_offset := -REAR_CAVITY_DEPTH
    var side_depth := REAR_CAVITY_DEPTH - FACE_BOARD_THICKNESS
    var side_center := -(FACE_BOARD_THICKNESS + side_depth * 0.5)

    _add_oriented_visual_box(
        "RearDropBack",
        Vector3(FACE_WIDTH - FRAME_RAIL_WIDTH, 0.012, FACE_LENGTH - FRAME_RAIL_WIDTH),
        _target_point(0.0, FACE_LENGTH * 0.5, cavity_offset),
        basis,
        hole_void_material
    )

    for side in [-1.0, 1.0]:
        _add_oriented_visual_box(
            "RearDropSide_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.020, side_depth, FACE_LENGTH),
            _target_point(side * FACE_WIDTH * 0.5, FACE_LENGTH * 0.5, side_center),
            basis,
            cabinet_material
        )

func _add_drain_throat(node_name: String, u: float, v: float) -> void:
    # The throat starts behind the visible face, so its front annulus can never
    # z-fight with the target deck. Its inner diameter matches the playable cut.
    _add_csg_ring(
        node_name,
        u,
        v,
        PLAY_HOLE_RADIUS + THROAT_THICKNESS * 0.5,
        FACE_BOARD_THICKNESS - 0.035 * INCH,
        THROAT_THICKNESS,
        -FACE_BOARD_THICKNESS + 0.020 * INCH
    )

func _add_score_reset_point(points: int, u: float, v: float) -> void:
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
    shape.radius = PLAY_HOLE_RADIUS * 0.96
    shape.height = 0.030
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_score_reset_entered.bind(points))

func _add_csg_ring(
    node_name: String,
    u: float,
    v: float,
    center_radius: float,
    height: float,
    thickness: float,
    normal_start: float
) -> void:
    var frame := Node3D.new()
    frame.name = "%sFrame" % node_name
    frame.position = _target_point(u, v, normal_start)
    frame.basis = Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    add_child(frame)

    var ring := CSGCombiner3D.new()
    ring.name = node_name
    ring.use_collision = true
    ring.collision_layer = 1
    ring.collision_mask = 1
    frame.add_child(ring)

    var outer := CSGCylinder3D.new()
    outer.name = "Outer"
    outer.radius = center_radius + thickness * 0.5
    outer.height = height
    outer.sides = CIRCLE_SEGMENTS
    outer.smooth_faces = true
    outer.material = hole_material
    outer.position.y = height * 0.5
    ring.add_child(outer)

    var inner := CSGCylinder3D.new()
    inner.name = "InnerCut"
    inner.radius = maxf(0.001, center_radius - thickness * 0.5)
    inner.height = height + 0.010
    inner.sides = CIRCLE_SEGMENTS
    inner.smooth_faces = true
    inner.operation = CSGShape3D.OPERATION_SUBTRACTION
    inner.position.y = height * 0.5
    ring.add_child(inner)

func _add_csg_u_wall(
    node_name: String,
    center_v: float,
    radius: float,
    leg_top_v: float,
    height: float,
    thickness: float
) -> void:
    var frame := Node3D.new()
    frame.name = "%sFrame" % node_name
    frame.position = _target_point(0.0, center_v, RING_LIFT)
    frame.basis = Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    add_child(frame)

    var shape := CSGCombiner3D.new()
    shape.name = node_name
    shape.use_collision = true
    shape.collision_layer = 1
    shape.collision_mask = 1
    frame.add_child(shape)

    var outer := CSGCylinder3D.new()
    outer.name = "LowerOuter"
    outer.radius = radius + thickness * 0.5
    outer.height = height
    outer.sides = CIRCLE_SEGMENTS
    outer.smooth_faces = true
    outer.material = hole_material
    outer.position.y = height * 0.5
    shape.add_child(outer)

    var inner := CSGCylinder3D.new()
    inner.name = "LowerInnerCut"
    inner.radius = radius - thickness * 0.5
    inner.height = height + 0.010
    inner.sides = CIRCLE_SEGMENTS
    inner.smooth_faces = true
    inner.operation = CSGShape3D.OPERATION_SUBTRACTION
    inner.position.y = height * 0.5
    shape.add_child(inner)

    # Remove the entire upper half of the annulus. The two straight legs below
    # are then unioned into the remaining lower semicircle.
    var upper_cut := CSGBox3D.new()
    upper_cut.name = "UpperHalfCut"
    upper_cut.size = Vector3(
        radius * 2.0 + thickness * 4.0,
        height + 0.020,
        radius * 2.0 + thickness * 4.0
    )
    upper_cut.position = Vector3(
        0.0,
        height * 0.5,
        radius + thickness
    )
    upper_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
    shape.add_child(upper_cut)

    var leg_length := maxf(0.001, leg_top_v - center_v)
    for side in [-1.0, 1.0]:
        var leg := CSGBox3D.new()
        leg.name = "Leg_%s" % ("L" if side < 0.0 else "R")
        leg.size = Vector3(thickness, height, leg_length + thickness * 0.5)
        leg.position = Vector3(
            side * radius,
            height * 0.5,
            leg_length * 0.5
        )
        leg.material = hole_material
        shape.add_child(leg)

func _add_face_label(
    node_name: String,
    points: int,
    u: float,
    v: float,
    radius: float
) -> void:
    var label := Label3D.new()
    label.name = node_name
    label.text = str(points)
    label.font_size = 58 if points < 100 else 48
    label.pixel_size = 0.00135
    label.modulate = Color(0.08, 0.055, 0.040)
    label.outline_size = 0
    label.position = (
        _target_point(u, v)
        - FACE_V * (radius + GUIDE_THICKNESS * 0.5 + LABEL_FACE_OFFSET)
        + FACE_N * (GUIDE_HEIGHT * 0.55)
    )
    label.basis = Basis(FACE_RIGHT, FACE_N, -FACE_V).orthonormalized()
    add_child(label)

func _build_backboard() -> void:
    var marquee_center_y := 1.82
    _add_static_box(
        "Backboard",
        Vector3(FACE_WIDTH + 0.06, 0.52, 0.055),
        Vector3(0.0, 1.60, BACK_Z + 0.060),
        blue_material
    )
    _add_visual_box(
        "Marquee",
        Vector3(HEAD_WIDTH - 0.07, 0.42, 0.065),
        Vector3(0.0, marquee_center_y, BACK_Z + 0.078),
        blue_material
    )
    _add_visual_box(
        "MarqueeTopTrim",
        Vector3(HEAD_WIDTH - 0.05, 0.040, 0.075),
        Vector3(0.0, marquee_center_y + 0.23, BACK_Z + 0.085),
        gold_material
    )

    var title := Label3D.new()
    title.text = "SLOT BALL"
    title.font_size = 82
    title.pixel_size = 0.0020
    title.modulate = Color(0.95, 0.72, 0.16)
    title.outline_size = 8
    title.outline_modulate = Color(0.32, 0.055, 0.035)
    title.position = Vector3(0.0, marquee_center_y, BACK_Z + 0.118)
    add_child(title)

func _build_invisible_containment() -> void:
    var head_front_z := ALLEY_REAR_Z + 0.14
    var head_depth := head_front_z - BACK_Z
    var head_center_z := (head_front_z + BACK_Z) * 0.5

    _add_invisible_static_box(
        "InvisibleTargetCeiling",
        Vector3(HEAD_WIDTH - 0.08, 0.05, head_depth),
        Vector3(0.0, 2.05, head_center_z)
    )

    var side_x := HEAD_WIDTH * 0.5 - 0.080
    for side in [-1.0, 1.0]:
        _add_invisible_static_box(
            "InvisibleTargetSide_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.025, 1.55, head_depth),
            Vector3(side * side_x, 1.28, head_center_z)
        )
