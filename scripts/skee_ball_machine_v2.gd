class_name SkeeBallMachineV2
extends SkeeBallMachine

# Target assembly based on the measured real-machine target board and current
# Skee-Ball Classic service documentation. The board owns seven true score
# openings; the white target pieces are mounted above/through that board.
const GUIDE_HEIGHT := 4.0 * INCH
const GUIDE_THICKNESS := 0.25 * INCH
const OUTER_10_RADIUS := 0.245
const OUTER_10_V := 0.285
const INNER_20_RADIUS := 0.150
const INNER_20_V := 0.360
const ROUND_SEGMENTS := 72
const FRAME_RAIL_WIDTH := 1.25 * INCH
const FRAME_RAIL_DEPTH := 1.50 * INCH
const REAR_DROP_DEPTH := 0.145
const THROAT_THICKNESS := 0.22 * INCH

func _all_score_targets() -> Array[Dictionary]:
    return [
        {"points": 10, "u": 0.0, "v": V10, "id": "10"},
        {"points": 20, "u": 0.0, "v": V20, "id": "20"},
        {"points": 30, "u": 0.0, "v": V30, "id": "30"},
        {"points": 40, "u": 0.0, "v": V40, "id": "40"},
        {"points": 50, "u": 0.0, "v": V50, "id": "50"},
        {"points": 100, "u": -HUNDO_X, "v": V100, "id": "100L"},
        {"points": 100, "u": HUNDO_X, "v": V100, "id": "100R"},
    ]

func _upper_chute_targets() -> Array[Dictionary]:
    return [
        {"points": 30, "u": 0.0, "v": V30, "id": "30"},
        {"points": 40, "u": 0.0, "v": V40, "id": "40"},
        {"points": 50, "u": 0.0, "v": V50, "id": "50"},
        {"points": 100, "u": -HUNDO_X, "v": V100, "id": "100L"},
        {"points": 100, "u": HUNDO_X, "v": V100, "id": "100R"},
    ]

func _build_target_board() -> void:
    _build_target_frame()
    _build_perforated_target_board()
    _build_rear_drop_cavity()

    # The lower scoring structure is a pair of large capture/guide walls. The
    # actual 10 and 20 score openings are separate 4-inch drains in the board.
    _add_round_wall(
        "Guide10",
        0.0,
        OUTER_10_V,
        OUTER_10_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS,
        0.0
    )
    _add_wall_label("Guide10Label", 10, 0.0, OUTER_10_V, OUTER_10_RADIUS, GUIDE_HEIGHT)

    _add_round_wall(
        "Guide20",
        0.0,
        INNER_20_V,
        INNER_20_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS,
        0.0
    )
    _add_wall_label("Guide20Label", 20, 0.0, INNER_20_V, INNER_20_RADIUS, GUIDE_HEIGHT)

    # Higher-value targets have their familiar raised white chutes centered on
    # their physical openings in the target board.
    for target in _upper_chute_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var target_id := String(target["id"])
        var ring_radius := TARGET_HOLE_RADIUS + GUIDE_THICKNESS * 0.5
        _add_round_wall(
            "TargetRing_%s" % target_id,
            u,
            v,
            ring_radius,
            GUIDE_HEIGHT,
            GUIDE_THICKNESS,
            0.0
        )
        _add_wall_label(
            "TargetLabel_%s" % target_id,
            points,
            u,
            v,
            ring_radius,
            GUIDE_HEIGHT
        )

    # Every score value, including 10 and 20, has a real hole through the
    # backing. A flush white throat lines that cut and the reset sensor sits at
    # the mouth where the ball actually leaves the playfield.
    for target in _all_score_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var target_id := String(target["id"])
        _add_drain_throat("Drain_%s" % target_id, u, v)
        _add_score_reset_point(points, u, v)

func _build_target_frame() -> void:
    var frame_basis := Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    var half_width := TARGET_WIDTH * 0.5
    var half_length := TARGET_LENGTH * 0.5
    var rail_half := FRAME_RAIL_WIDTH * 0.5
    var frame_depth_center := -FRAME_RAIL_DEPTH * 0.5

    # The target is an inset panel carried by a perimeter frame rather than a
    # free-floating red rectangle.
    _add_oriented_static_box(
        "TargetFrameLeft",
        Vector3(FRAME_RAIL_WIDTH, FRAME_RAIL_DEPTH, TARGET_LENGTH + FRAME_RAIL_WIDTH * 2.0),
        _target_point(-half_width - rail_half, half_length, frame_depth_center),
        frame_basis,
        cabinet_material,
        target_physics_material
    )
    _add_oriented_static_box(
        "TargetFrameRight",
        Vector3(FRAME_RAIL_WIDTH, FRAME_RAIL_DEPTH, TARGET_LENGTH + FRAME_RAIL_WIDTH * 2.0),
        _target_point(half_width + rail_half, half_length, frame_depth_center),
        frame_basis,
        cabinet_material,
        target_physics_material
    )
    _add_oriented_static_box(
        "TargetFrameBottom",
        Vector3(TARGET_WIDTH, FRAME_RAIL_DEPTH, FRAME_RAIL_WIDTH),
        _target_point(0.0, -rail_half, frame_depth_center),
        frame_basis,
        cabinet_material,
        target_physics_material
    )
    _add_oriented_static_box(
        "TargetFrameTop",
        Vector3(TARGET_WIDTH, FRAME_RAIL_DEPTH, FRAME_RAIL_WIDTH),
        _target_point(0.0, TARGET_LENGTH + rail_half, frame_depth_center),
        frame_basis,
        cabinet_material,
        target_physics_material
    )

    # Visible rear support rails make the panel read as an installed target
    # assembly when inspected with the unlocked debug camera.
    for side in [-1.0, 1.0]:
        _add_oriented_static_box(
            "TargetRearSupport_%s" % ("L" if side < 0.0 else "R"),
            Vector3(FRAME_RAIL_WIDTH * 0.72, FRAME_RAIL_DEPTH, TARGET_LENGTH * 0.82),
            _target_point(
                side * TARGET_WIDTH * 0.38,
                TARGET_LENGTH * 0.52,
                -REAR_DROP_DEPTH * 0.48
            ),
            frame_basis,
            cabinet_material,
            target_physics_material
        )

func _build_perforated_target_board() -> void:
    var frame := Node3D.new()
    frame.name = "PerforatedTargetBoardFrame"
    frame.position = _target_point(
        0.0,
        TARGET_LENGTH * 0.5,
        -TARGET_BOARD_THICKNESS * 0.5
    )
    frame.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    add_child(frame)

    var assembly := CSGCombiner3D.new()
    assembly.name = "SevenHoleTargetBoard"
    assembly.use_collision = true
    assembly.collision_layer = 1
    assembly.collision_mask = 1
    frame.add_child(assembly)

    var plate := CSGBox3D.new()
    plate.name = "TargetPlate"
    plate.size = Vector3(TARGET_WIDTH, TARGET_BOARD_THICKNESS, TARGET_LENGTH)
    plate.material = target_material
    assembly.add_child(plate)

    for target in _all_score_targets():
        var cut := CSGCylinder3D.new()
        cut.name = "ScoreCut_%s" % String(target["id"])
        cut.radius = TARGET_HOLE_RADIUS
        cut.height = TARGET_BOARD_THICKNESS * 3.0
        cut.sides = ROUND_SEGMENTS
        cut.smooth_faces = true
        cut.operation = CSGShape3D.OPERATION_SUBTRACTION
        cut.position = Vector3(
            float(target["u"]),
            0.0,
            float(target["v"]) - TARGET_LENGTH * 0.5
        )
        assembly.add_child(cut)

func _build_rear_drop_cavity() -> void:
    var basis := Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    var cavity_offset := -REAR_DROP_DEPTH

    # One common dark drop chamber sits behind the target. There are no fake
    # black disks plugging individual score holes; the player sees into this
    # shared open cavity through every cutout.
    _add_oriented_visual_box(
        "RearDropBack",
        Vector3(TARGET_WIDTH - FRAME_RAIL_WIDTH * 0.8, 0.012, TARGET_LENGTH - FRAME_RAIL_WIDTH),
        _target_point(0.0, TARGET_LENGTH * 0.5, cavity_offset),
        basis,
        hole_void_material
    )

    var side_depth := REAR_DROP_DEPTH - TARGET_BOARD_THICKNESS
    var side_center_normal := -(TARGET_BOARD_THICKNESS + side_depth * 0.5)
    for side in [-1.0, 1.0]:
        _add_oriented_visual_box(
            "RearDropSide_%s" % ("L" if side < 0.0 else "R"),
            Vector3(0.018, side_depth, TARGET_LENGTH),
            _target_point(side * TARGET_WIDTH * 0.5, TARGET_LENGTH * 0.5, side_center_normal),
            basis,
            cabinet_material
        )

    _add_oriented_visual_box(
        "RearDropLowerShelf",
        Vector3(TARGET_WIDTH, side_depth, 0.020),
        _target_point(0.0, -0.010, side_center_normal),
        basis,
        cabinet_material
    )

func _add_drain_throat(node_name: String, u: float, v: float) -> void:
    var wall_center_radius := TARGET_HOLE_RADIUS + THROAT_THICKNESS * 0.5
    _add_round_wall(
        node_name,
        u,
        v,
        wall_center_radius,
        TARGET_BOARD_THICKNESS * 1.08,
        THROAT_THICKNESS,
        -TARGET_BOARD_THICKNESS * 1.04
    )

func _add_round_wall(
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

    for index in range(ROUND_SEGMENTS):
        var angle0 := TAU * float(index) / float(ROUND_SEGMENTS)
        var angle1 := TAU * float(index + 1) / float(ROUND_SEGMENTS)
        var radial0 := TARGET_RIGHT * cos(angle0) + TARGET_V * sin(angle0)
        var radial1 := TARGET_RIGHT * cos(angle1) + TARGET_V * sin(angle1)

        var outer0 := center + radial0 * outer_radius
        var outer1 := center + radial1 * outer_radius
        var inner0 := center + radial0 * inner_radius
        var inner1 := center + radial1 * inner_radius
        var outer0_top := outer0 + TARGET_N * height
        var outer1_top := outer1 + TARGET_N * height
        var inner0_top := inner0 + TARGET_N * height
        var inner1_top := inner1 + TARGET_N * height

        _add_quad(surface, outer0, outer1, outer1_top, outer0_top)
        _add_quad(surface, inner1, inner0, inner0_top, inner1_top)
        _add_quad(surface, outer0_top, outer1_top, inner1_top, inner0_top)
        _add_quad(surface, inner0, inner1, outer1, outer0)

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

func _add_wall_label(
    node_name: String,
    points: int,
    u: float,
    v: float,
    radius: float,
    height: float
) -> void:
    var label := Label3D.new()
    label.name = node_name
    label.text = str(points)
    label.font_size = 64 if points < 100 else 52
    label.pixel_size = 0.0015
    label.modulate = Color(0.10, 0.075, 0.055)
    label.outline_size = 2
    label.outline_modulate = Color(0.94, 0.93, 0.89)
    label.position = (
        _target_point(u, v)
        - TARGET_V * (radius + GUIDE_THICKNESS * 0.55)
        + TARGET_N * (height * 0.56)
    )
    label.basis = Basis(TARGET_RIGHT, TARGET_N, -TARGET_V).orthonormalized()
    add_child(label)
