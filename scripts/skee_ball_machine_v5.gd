class_name SkeeBallMachineV5
extends SkeeBallMachineV4

# Restore the previously accepted physical separation between the kicker/ramp
# and the scoring platform. V4's STL-derived target ratios remain unchanged.
const RESTORED_MISS_SLOT := 5.75 * INCH
const RESTORED_FACE_BOTTOM := Vector3(
    0.0,
    0.6600,
    HOP_END_Z - RESTORED_MISS_SLOT
)

func _target_point(u: float, v: float, n: float = 0.0) -> Vector3:
    return RESTORED_FACE_BOTTOM + Vector3.RIGHT * u + FV * v + FN * n
