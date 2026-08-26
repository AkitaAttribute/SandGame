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

const uint MAX_ACTIVE_STEPS = 90u;
const uint QUIET_STEPS_TO_LOCK = 4u;
const float MIN_VISIBLE_STEP = 0.0012;
const float EXPIRED_LATERAL_KEEP = 0.55;

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

    age = min(age + 1u, 0xffffu);

    vec3 movement = positions[id].xyz - previous_positions[id].xyz;
    float displacement = length(movement);
    if (displacement < MIN_VISIBLE_STEP) {
        quiet_steps = min(quiet_steps + 1u, 0xffffu);
    } else {
        quiet_steps = 0u;
    }

    if (age >= MAX_ACTIVE_STEPS) {
        // Expired grains become non-propagating but remain physically active.
        // Gravity and the existing grain/floor collision solver continue to
        // place them on the nearest valid support surface.
        grain_states[id] = 1u;
        velocities[id].x *= EXPIRED_LATERAL_KEEP;
        velocities[id].z *= EXPIRED_LATERAL_KEEP;
    }

    if (quiet_steps >= QUIET_STEPS_TO_LOCK) {
        // Four consecutive sub-millimetre-ish steps are effectively impossible
        // for a truly airborne grain under gravity, but common for settled PBD
        // jitter. Lock only after that hysteresis window.
        grain_states[id] = 0u;
        velocities[id] = vec4(0.0);
        previous_positions[id] = positions[id];
        wake_impulses[id] = ivec4(0);
        return;
    }

    wake_impulses[id].w = int((quiet_steps << 16u) | age);
}
