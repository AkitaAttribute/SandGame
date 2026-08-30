class_name SkeeBallMachineV2
extends SkeeBallMachine

# Classic target geometry rebuilt from real-machine photography and printable
# skee-ball references. The large 10/20 rings are guide walls, while the
# 30/40/50/100 targets are true cups through the target board.
const GUIDE_HEIGHT := 4.0 * INCH
const GUIDE_THICKNESS := 0.25 * INCH
const OUTER_10_RADIUS := 0.282
const OUTER_10_V := 0.285
const INNER_20_RADIUS := 0.178
const INNER_20_V := 0.360
const ROUND_SEGMENTS := 72

func _cup_targets() -> Array[Dictionary]:
    return [
        {"points": 30, "u": 0.0, "v": V30},
        {"points": 40, "u": 0.0, "v": V40},
        {"points": 50, "u": 0.0, "v": V50},
        {"points": 100, "u": -HUNDO_X, "v": V100},
        {"points": 100, "u": HUNDO_X, "v": V100},
    ]

func _build_target_board() -> void:
    _build_csg_backing()

    # The characteristic classic lower target: two large smooth guide rings.
    _add_round_wall(
        "Guide10",
        0.0,
        OUTER_10_V,
        OUTER_10_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS
    )
    _add_wall_label("Guide10Label", 10, 0.0, OUTER_10_V, OUTER_10_RADIUS, GUIDE_HEIGHT)

    _add_round_wall(
        "Guide20",
        0.0,
        INNER_20_V,
        INNER_20_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS
    )
    _add_wall_label("Guide20Label", 20, 0.0, INNER_20_V, INNER_20_RADIUS, GUIDE_HEIGHT)

    # The upper values are actual open cups. Their white walls intersect the
    # backing and the CSG plate is physically absent inside each cup.
    for target in _cup_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var wall_center_radius := TARGET_HOLE_RADIUS + GUIDE_THICKNESS * 0.5
        _add_round_wall(
            "Cup%d_%s" % [points, str(snappedf(u, 0.001))],
            u,
            v,
            wall_center_radius,
            GUIDE_HEIGHT,
            GUIDE_THICKNESS
        )
        _add_hole_void(u, v, points)
        _add_wall_label(
            "Cup%dLabel_%s" % [points, str(snappedf(u, 0.001))],
            points,
            u,
            v,
            wall_center_radius,
            GUIDE_HEIGHT
        )
        _add_score_reset_point(points, u, v)

    _add_guide_score_plane()

func _build_csg_backing() -> void:
    var frame := Node3D.new()
    frame.name = "ClassicTargetBacking"
    frame.position = _target_point(
        0.0,
        TARGET_LENGTH * 0.5,
        -TARGET_BOARD_THICKNESS * 0.5
    )
    frame.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    add_child(frame)

    var assembly := CSGCombiner3D.new()
    assembly.name = "PerforatedBackingCSG"
    assembly.use_collision = true
    assembly.collision_layer = 1
    assembly.collision_mask = 1
    frame.add_child(assembly)

    var plate := CSGBox3D.new()
    plate.name = "TargetPlate"
    plate.size = Vector3(TARGET_WIDTH, TARGET_BOARD_THICKNESS, TARGET_LENGTH)
    plate.material = target_material
    assembly.add_child(plate)

    for target in _cup_targets():
        var cut := CSGCylinder3D.new()
        cut.name = "Cut%d" % int(target["points"])
        cut.radius = TARGET_HOLE_RADIUS
        cut.height = TARGET_BOARD_THICKNESS * 2.5
        cut.sides = ROUND_SEGMENTS
        cut.smooth_faces = true
        cut.operation = CSGShape3D.OPERATION_SUBTRACTION
        cut.position = Vector3(
            float(target["u"]),
            0.0,
            float(target["v"]) - TARGET_LENGTH * 0.5
        )
        assembly.add_child(cut)

func _add_round_wall(
    node_name: String,
    u: float,
    v: float,
    center_radius: float,
    height: float,
    thickness: float
) -> void:
    var center := _target_point(u, v)
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

        # Outside, inside and rounded-wall cap surfaces.
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
    # Text is mounted on the down-lane face of the white scoring wall.
    label.basis = Basis(TARGET_RIGHT, TARGET_N, -TARGET_V).orthonormalized()
    add_child(label)

func _add_guide_score_plane() -> void:
    var area := Area3D.new()
    area.name = "Guide10And20ScorePlane"
    area.position = _target_point(0.0, OUTER_10_V, 0.004)
    area.basis = Basis(TARGET_RIGHT, TARGET_N, TARGET_V).orthonormalized()
    area.collision_layer = 0
    area.collision_mask = 1
    area.monitoring = true
    add_child(area)

    var collision := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = OUTER_10_RADIUS - GUIDE_THICKNESS * 0.60
    shape.height = 0.014
    collision.shape = shape
    area.add_child(collision)
    area.body_entered.connect(_on_guide_score_entered)

func _on_guide_score_entered(body: Node3D) -> void:
    if not (body is SkeeBallBall):
        return

    var ball := body as SkeeBallBall
    if ball.scored or not ball.launched:
        return

    var local_position := to_local(ball.global_position)
    var relative := local_position - TARGET_BOTTOM
    var u := relative.dot(TARGET_RIGHT)
    var v := relative.dot(TARGET_V)

    # A ball entering an upper cup gets that cup's score, not a lower guide score.
    for target in _cup_targets():
        var cup_delta := Vector2(
            u - float(target["u"]),
            v - float(target["v"])
        )
        if cup_delta.length() <= TARGET_HOLE_RADIUS * 1.10:
            return

    var distance_20 := Vector2(u, v - INNER_20_V).length()
    var distance_10 := Vector2(u, v - OUTER_10_V).length()
    var points := 0

    if distance_20 <= INNER_20_RADIUS - GUIDE_THICKNESS * 0.75:
        points = 20
    elif distance_10 <= OUTER_10_RADIUS - GUIDE_THICKNESS * 0.75:
        points = 10

    if points <= 0:
        return

    ball.mark_scored()
    scored.emit(points, ball)
