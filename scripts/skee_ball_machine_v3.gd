class_name SkeeBallMachineV3
extends SkeeBallMachineV2

# Physics-first reproduction of the classic target shown in the supplied
# reference image. Commercial Classic documentation gives 3-inch balls,
# 4-inch playfield holes, 4-inch-high target rubber, and the replacement-strip
# lengths used below to reconstruct the target radii.
const FACE_WIDTH := 33.0 * INCH
const HEAD_WIDTH := 36.0 * INCH
const FACE_LENGTH := 38.0 * INCH
const FACE_BOARD_THICKNESS := 0.75 * INCH
const FACE_V := Vector3(0.0, 0.70710678, -0.70710678)
const FACE_N := Vector3(0.0, 0.70710678, 0.70710678)
const FACE_RIGHT := Vector3.RIGHT

# A physical machine leaves a miss slot between the kicker and target. Keep it
# only slightly wider than the 3-inch commercial ball instead of the huge gap
# used by the earlier prototype.
const MISS_SLOT := 3.40 * INCH
const FACE_BOTTOM := Vector3(0.0, 0.64695, -0.71406)

# Target replacement-strip lengths from the Classic service parts list.
# Circular strip length -> wall center-line radius.
const U_CENTER_V := 13.0 * INCH
const U_RADIUS := 13.0 * INCH
const U_LEG_TOP_V := 38.0 * INCH
const BIG_CIRCLE_RADIUS := (60.0 * INCH) / TAU
const R30 := (21.25 * INCH) / TAU
const R40 := (19.44 * INCH) / TAU
const R50 := (17.56 * INCH) / TAU
const R100 := (13.31 * INCH) / TAU
const CIRCLE_SEGMENTS := 128
const RING_LIFT := 0.0015
const REAR_CAVITY_DEPTH := 6.0 * INCH

func _build_materials() -> void:
    super._build_materials()
    # Match the dark target deck / white rubber look while keeping everything
    # matte enough that grazing-angle highlights do not shimmer.
    target_material.albedo_color = Color(0.18, 0.070, 0.040)
    target_material.roughness = 0.94
    hole_material.albedo_color = Color(0.94, 0.93, 0.89)
    hole_material.roughness = 0.72
    hole_material.metallic = 0.0
    target_physics_material.friction = 0.80
    target_physics_material.bounce = 0.025

func _target_point(u: float, v: float, normal_offset: float = 0.0) -> Vector3:
    return FACE_BOTTOM + FACE_RIGHT * u + FACE_V * v + FACE_N * normal_offset

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

    # Yellow rails visually frame the single active machine, as in the supplied
    # cabinet reference. They also provide honest physical side containment.
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

    # 10-point boundary: a wide U. The chosen width deliberately leaves a
    # greater-than-ball-diameter bypass lane outside each leg.
    _add_10_u_wall()
    _add_face_label("Target10Label", 10, 0.0, U_CENTER_V, U_RADIUS)

    # Large full circle that forms the next capture region.
    _add_clean_round_wall(
        "Target20Circle",
        0.0,
        U_CENTER_V,
        BIG_CIRCLE_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS,
        RING_LIFT
    )
    _add_face_label("Target20Label", 20, 0.0, U_CENTER_V, BIG_CIRCLE_RADIUS)

    # The progressively smaller targets use the documented replacement-strip
    # lengths, so their openings/capture walls are no longer arbitrary.
    _add_scoring_cup("Target30", 30, 0.0, V30, R30)
    _add_scoring_cup("Target40", 40, 0.0, V40, R40)
    _add_scoring_cup("Target50", 50, 0.0, V50, R50)
    _add_scoring_cup("Target100L", 100, -HUNDO_X, V100, R100)
    _add_scoring_cup("Target100R", 100, HUNDO_X, V100, R100)

    # All seven values are real 4-inch backing holes. 10 and 20 are flush
    # drains guided by the larger walls rather than fake scoring volumes.
    for target in _all_score_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var target_id := String(target["id"])
        _add_drain_throat("Drain_%s" % target_id, u, v)
        _add_score_reset_point(points, u, v)

func _add_scoring_cup(node_name: String, points: int, u: float, v: float, radius: float) -> void:
    _add_clean_round_wall(
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
        cut.radius = TARGET_HOLE_RADIUS
        cut.height = FACE_BOARD_THICKNESS * 3.0
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
    var wall_center_radius := TARGET_HOLE_RADIUS + THROAT_THICKNESS * 0.5
    # End the throat slightly behind the visible face. This avoids a coplanar
    # annular surface at the same depth as the target deck (z-fighting).
    _add_clean_round_wall(
        node_name,
        u,
        v,
        wall_center_radius,
        FACE_BOARD_THICKNESS - 0.002,
        THROAT_THICKNESS,
        -FACE_BOARD_THICKNESS + 0.001
    )

func _add_score_reset_point(points: int, u: float, v: float) -> void:
    var area := Area3D.new()
    area.name = "ScoreReset_%d" % points
    area.position = _target_point(u, v, -0.006)
    area.basis = Basis(FACE_RIGHT, FACE_N, FACE_V).orthonormalized()
    area.collision_layer = 0
    area.collision_mask = 1
    area.monitoring = true
    add_child(area)

    var collision := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = TARGET_HOLE_RADIUS * 0.97
    shape.height = 0.026
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_score_reset_entered.bind(points))

func _add_10_u_wall() -> void:
    var path: Array[Vector2] = []
    path.append(Vector2(-U_RADIUS, U_LEG_TOP_V))
    path.append(Vector2(-U_RADIUS, U_CENTER_V))

    var arc_segments := 72
    for index in range(arc_segments + 1):
        var t := float(index) / float(arc_segments)
        var angle := PI + PI * t
        path.append(Vector2(
            cos(angle) * U_RADIUS,
            U_CENTER_V + sin(angle) * U_RADIUS
        ))

    path.append(Vector2(U_RADIUS, U_LEG_TOP_V))
    _add_clean_path_wall("Target10U", path, GUIDE_HEIGHT, GUIDE_THICKNESS, RING_LIFT)

func _add_clean_path_wall(
    node_name: String,
    path: Array[Vector2],
    height: float,
    thickness: float,
    normal_start: float
) -> void:
    if path.size() < 2:
        return

    var left: Array[Vector2] = []
    var right: Array[Vector2] = []
    var half_thickness := thickness * 0.5

    # Miter the path offsets using an averaged tangent at each point. This keeps
    # the U continuous rather than leaving tiny per-segment cracks or overlaps.
    for index in range(path.size()):
        var tangent: Vector2
        if index == 0:
            tangent = path[1] - path[0]
        elif index == path.size() - 1:
            tangent = path[index] - path[index - 1]
        else:
            tangent = path[index + 1] - path[index - 1]
        tangent = tangent.normalized()
        var side := Vector2(-tangent.y, tangent.x) * half_thickness
        left.append(path[index] + side)
        right.append(path[index] - side)

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(hole_material)

    for index in range(path.size() - 1):
        var l0 := _target_point(left[index].x, left[index].y, normal_start)
        var l1 := _target_point(left[index + 1].x, left[index + 1].y, normal_start)
        var r0 := _target_point(right[index].x, right[index].y, normal_start)
        var r1 := _target_point(right[index + 1].x, right[index + 1].y, normal_start)
        var l0t := l0 + FACE_N * height
        var l1t := l1 + FACE_N * height
        var r0t := r0 + FACE_N * height
        var r1t := r1 + FACE_N * height

        _add_quad(surface, l0, l1, l1t, l0t)
        _add_quad(surface, r1, r0, r0t, r1t)
        _add_quad(surface, l0t, l1t, r1t, r0t)

    # Close only the two ends. The wall deliberately has no bottom face against
    # the backing, eliminating the previous coplanar flashing artifacts.
    var first_l := _target_point(left[0].x, left[0].y, normal_start)
    var first_r := _target_point(right[0].x, right[0].y, normal_start)
    var last_l := _target_point(left[-1].x, left[-1].y, normal_start)
    var last_r := _target_point(right[-1].x, right[-1].y, normal_start)
    _add_quad(surface, first_r, first_l, first_l + FACE_N * height, first_r + FACE_N * height)
    _add_quad(surface, last_l, last_r, last_r + FACE_N * height, last_l + FACE_N * height)

    _commit_wall_mesh(node_name, surface)

func _add_clean_round_wall(
    node_name: String,
    u: float,
    v: float,
    center_radius: float,
    height: float,
    thickness: float,
    normal_start: float
) -> void:
    var center := _target_point(u, v, normal_start)
    var outer_radius := center_radius + thickness * 0.5
    var inner_radius := maxf(0.001, center_radius - thickness * 0.5)

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(hole_material)

    for index in range(CIRCLE_SEGMENTS):
        var a0 := TAU * float(index) / float(CIRCLE_SEGMENTS)
        var a1 := TAU * float(index + 1) / float(CIRCLE_SEGMENTS)
        var radial0 := FACE_RIGHT * cos(a0) + FACE_V * sin(a0)
        var radial1 := FACE_RIGHT * cos(a1) + FACE_V * sin(a1)

        var o0 := center + radial0 * outer_radius
        var o1 := center + radial1 * outer_radius
        var i0 := center + radial0 * inner_radius
        var i1 := center + radial1 * inner_radius
        var o0t := o0 + FACE_N * height
        var o1t := o1 + FACE_N * height
        var i0t := i0 + FACE_N * height
        var i1t := i1 + FACE_N * height

        _add_quad(surface, o0, o1, o1t, o0t)
        _add_quad(surface, i1, i0, i0t, i1t)
        _add_quad(surface, o0t, o1t, i1t, i0t)

    # No bottom annulus: it used to sit coplanar with the backing and caused
    # angle-dependent shimmering/flashing.
    _commit_wall_mesh(node_name, surface)

func _commit_wall_mesh(node_name: String, surface: SurfaceTool) -> void:
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

func _add_face_label(node_name: String, points: int, u: float, v: float, radius: float) -> void:
    var label := Label3D.new()
    label.name = node_name
    label.text = str(points)
    label.font_size = 68 if points < 100 else 54
    label.pixel_size = 0.00145
    label.modulate = Color(0.08, 0.055, 0.040)
    label.outline_size = 2
    label.outline_modulate = Color(0.96, 0.95, 0.91)
    label.position = (
        _target_point(u, v)
        - FACE_V * (radius + GUIDE_THICKNESS * 0.55)
        + FACE_N * (GUIDE_HEIGHT * 0.56 + 0.002)
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
