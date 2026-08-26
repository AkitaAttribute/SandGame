#[compute]
#version 450

layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Positions {
    vec4 positions[];
};
layout(set = 0, binding = 1, std430) restrict buffer PreviousPositions {
    vec4 previous_positions[];
};
layout(set = 0, binding = 2, std430) restrict buffer Velocities {
    vec4 velocities[];
};
layout(set = 0, binding = 9, std430) restrict buffer GrainStates {
    uint grain_states[];
};
layout(set = 0, binding = 12, std430) restrict buffer WakeImpulses {
    ivec4 wake_impulses[];
};

// The watchdog is deliberately inert during normal motion. Only after roughly
// three seconds does a still-active grain enter a non-propagating settling
// phase. It can then lock only after several genuinely tiny movement steps.
const uint NORMAL_ACTIVE_STEPS = 90u;
const uint QUIET_STEPS_TO_LOCK = 6u;
const float MIN_SETTLE_STEP = 0.0004;
const float EXPIRED_LATERAL_KEEP = 0.82;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= positions.length()) {
        return;
    }

    uint state = grain_states[id];
    if (state == 0u) {
        wake_impulses[id].w = 0;
        return;
    }

    uint packed = uint(wake_impulses[id].w);
    uint age = packed & 0xffffu;
    uint quiet_steps = (packed >> 16u) & 0xffffu;

    // If a grain that had already entered settling is hit again, a direct
    // actor/explosion wake raises its propagation state above 1. Treat that as
    // a fresh activation and give it a full normal-motion grace period again.
    if (age > NORMAL_ACTIVE_STEPS && state > 1u) {
        age = 1u;
        quiet_steps = 0u;
        wake_impulses[id].w = int(age);
        return;
    }

    // During the normal active window this pass must not alter state, velocity,
    // or quiet counters. The PBD solver owns all motion during this period.
    if (age < NORMAL_ACTIVE_STEPS) {
        age += 1u;
        wake_impulses[id].w = int(age);
        return;
    }

    // Lifetime expiry does not freeze the grain. It merely removes its ability
    // to wake further neighbors and gently sheds lateral energy. Gravity and
    // ordinary grain/floor collisions continue until it reaches valid support.
    grain_states[id] = 1u;
    velocities[id].x *= EXPIRED_LATERAL_KEEP;
    velocities[id].z *= EXPIRED_LATERAL_KEEP;

    vec3 movement = positions[id].xyz - previous_positions[id].xyz;
    float displacement = length(movement);
    if (displacement < MIN_SETTLE_STEP) {
        quiet_steps = min(quiet_steps + 1u, 0xffffu);
    } else {
        quiet_steps = 0u;
    }

    // Six consecutive sub-0.4 mm steps are a strong indication of settled PBD
    // jitter. A truly airborne grain will not satisfy this under gravity for
    // long enough to lock at the apex of its trajectory.
    if (quiet_steps >= QUIET_STEPS_TO_LOCK) {
        grain_states[id] = 0u;
        velocities[id] = vec4(0.0);
        previous_positions[id] = positions[id];
        wake_impulses[id] = ivec4(0);
        return;
    }

    age = min(age + 1u, 0xffffu);
    wake_impulses[id].w = int((quiet_steps << 16u) | age);
}
