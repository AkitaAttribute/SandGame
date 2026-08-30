class_name SkeeBallMachineV3
extends SkeeBallMachineV2

# The supplied Skeeball-Face STL is used only as a geometry reference. Its
# 25-unit score openings are normalized to the known 4-inch commercial holes.
# This preserves the STL's guide proportions without importing the STL itself.
const STL_HOLE_RADIUS := 12.5
const STL_TO_GAME := TARGET_HOLE_RADIUS / STL_HOLE_RADIUS
const STL_U_CENTER_V := 31.9719675
const STL_U_RADIUS := 74.0394554
const STL_INNER_CENTER_V := 40.1126980
const STL_INNER_RADIUS := 51.8740700

# Align the guide structures to the measured 10/20 drain positions already in
# the project. The seven hole centers themselves remain the measured values.
const STL_10_HOLE_V := -27.8822788
const STL_20_HOLE_V := 2.1373016
const GUIDE10_CENTER_V := V10 + (STL_U_CENTER_V - STL_10_HOLE_V) * STL_TO_GAME
const GUIDE10_RADIUS := STL_U_RADIUS * STL_TO_GAME
const GUIDE10_LEG_TOP_V := V100 + 1.25 * INCH
const GUIDE20_CENTER_V := V20 + (STL_INNER_CENTER_V - STL_20_HOLE_V) * STL_TO_GAME
const GUIDE20_RADIUS := STL_INNER_RADIUS * STL_TO_GAME
const SMOOTH_SEGMENTS := 96

func _build_target_board() -> void:
    # Keep V2's functional target frame, seven CSG backing holes, white drain
    # throats, common rear drop cavity, and mouth-mounted score/reset sensors.
    _build_target_frame()
    _build_perforated_target_board()
    _build_rear_drop_cavity()

    # Actual STL topology: the 10 guide is a U, not a full circle.
    _add_10_u_guide()
    _add_wall_label(
        "Guide10Label",
        10,
        0.0,
        GUIDE10_CENTER_V,
        GUIDE10_RADIUS,
        GUIDE_HEIGHT
    )

    # The 20 structure is the large complete inner ring seen in the STL.
    _add_round_wall(
        "Guide20",
        0.0,
        GUIDE20_CENTER_V,
        GUIDE20_RADIUS,
        GUIDE_HEIGHT,
        GUIDE_THICKNESS,
        0.0
    )
    _add_wall_label(
        "Guide20Label",
        20,
        0.0,
        GUIDE20_CENTER_V,
        GUIDE20_RADIUS,
        GUIDE_HEIGHT
    )

    # 30/40/50/100 remain raised cups around their physical drain holes.
    for target in _upper_chute_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var target_id := String(target["id"])
        var radius := TARGET_HOLE_RADIUS + GUIDE_THICKNESS * 0.5
        _add_round_wall(
            "TargetCup_%s" % target_id,
            u,
            v,
            radius,
            GUIDE_HEIGHT,
            GUIDE_THICKNESS,
            0.0
        )
        _add_wall_label(
            "TargetLabel_%s" % target_id,
            points,
            u,
            v,
            radius,
            GUIDE_HEIGHT
        )

    # Every value, including 10 and 20, drains through a real backing hole.
    for target in _all_score_targets():
        var points := int(target["points"])
        var u := float(target["u"])
        var v := float(target["v"])
        var target_id := String(target["id"])
        _add_drain_throat("Drain_%s" % target_id, u, v)
        _add_score_reset_point(points, u, v)

func _add_10_u_guide() -> void:
    var path: Array[Vector2] = []
    path.append(Vector2(-GUIDE10_RADIUS, GUIDE10_LEG_TOP_V))
    path.append(Vector2(-GUIDE10_RADIUS, GUIDE10_CENTER_V))

    var half_segments := int(SMOOTH_SEGMENTS / 2)
    for index in range(half_segments + 1):
        var t := float(index) / float(half_segments)
        var angle := PI + PI * t
        path.append(Vector2(
            cos(angle) * GUIDE10_RADIUS,
            GUIDE10_CENTER_V + sin(angle) * GUIDE10_RADIUS
        ))

    path.append(Vector2(GUIDE10_RADIUS, GUIDE10_LEG_TOP_V))
    _add_smooth_path_wall("Guide10U", path, GUIDE_HEIGHT, GUIDE_THICKNESS)

func _add_smooth_path_wall(
    node_name: String,
    path: Array[Vector2],
    height: float,
    thickness: float
) -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(hole_material)

    for index in range(path.size() - 1):
        var a2 := path[index]
        var b2 := path[index + 1]
        var tangent := b2 - a2
        if tangent.length_squared() < 0.0000001:
            continue
        tangent = tangent.normalized()
        var side := Vector2(-tangent.y, tangent.x) * (thickness * 0.5)

        var a_left := _target_point(a2.x + side.x, a2.y + side.y)
        var a_right := _target_point(a2.x - side.x, a2.y - side.y)
        var b_left := _target_point(b2.x + side.x, b2.y + side.y)
        var b_right := _target_point(b2.x - side.x, b2.y - side.y)
        var a_left_top := a_left + TARGET_N * height
        var a_right_top := a_right + TARGET_N * height
        var b_left_top := b_left + TARGET_N * height
        var b_right_top := b_right + TARGET_N * height

        _add_quad(surface, a_left, b_left, b_left_top, a_left_top)
        _add_quad(surface, b_right, a_right, a_right_top, b_right_top)
        _add_quad(surface, a_left_top, b_left_top, b_right_top, a_right_top)
        _add_quad(surface, a_right, b_right, b_left, a_left)

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
