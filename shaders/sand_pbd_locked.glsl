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
layout(set = 0, binding = 3, std430) restrict buffer Corrections {
    vec4 corrections[];
};
layout(set = 0, binding = 4, std430) restrict buffer CellCounts {
    uint cell_counts[];
};
layout(set = 0, binding = 5, std430) restrict buffer CellParticles {
    uint cell_particles[];
};
layout(set = 0, binding = 6, std430) readonly restrict buffer Commands {
    vec4 command_data[];
};
layout(set = 0, binding = 7, rgba32f) uniform writeonly image2D position_image;
layout(set = 0, binding = 8, std430) restrict buffer SurfaceBits {
    uint surface_bits[];
};
layout(set = 0, binding = 9, std430) restrict buffer GrainStates {
    uint grain_states[];
};
layout(set = 0, binding = 10, std430) restrict buffer GrainSleep {
    uint grain_sleep[];
};
layout(set = 0, binding = 11, std430) restrict buffer ActiveCount {
    uint active_count[];
};
layout(set = 0, binding = 12, std430) restrict buffer WakeImpulses {
    ivec4 wake_impulses[];
};

layout(push_constant, std430) uniform Params {
    uint phase;
    uint particle_count;
    uint grid_x;
    uint grid_z;

    uint max_cell_particles;
    uint command_count;
    uint iteration;
    uint axis_particles;

    float dt;
    float grain_radius;
    float boundary_half_extent;
    float cell_size;

    float gravity;
    float friction;
    float restitution;
    float velocity_damping;

    float packing_spacing;
    uint texture_width;
    uint surface_count;
    uint region_size;
} pc;

const uint EXPLOSION_WAKE_LEVEL = 5u;
const uint BODY_WAKE_LEVEL = 3u;
const uint FOOT_WAKE_LEVEL = 2u;

const float WAKE_IMPACT_SPEED = 0.72;
const float WAKE_PENETRATION = 0.0025;
const float WAKE_TRANSFER = 0.26;
const float WAKE_IMPULSE_SCALE = 4096.0;

const float CONTACT_CORRECTION_VELOCITY_TRANSFER = 0.18;
const float CONTACT_KEEP_PER_CONTACT = 0.64;
const float DENSE_SLEEP_SPEED = 0.22;
const float SINGLE_SLEEP_SPEED = 0.075;
const uint SLEEP_STEPS = 5u;
const float MAX_DAMPING_CONTACTS = 6.0;

uint grid_cell_count() {
    return pc.grid_x * pc.grid_z;
}

uvec2 cell_coords(vec3 p) {
    float shifted_x = p.x + pc.boundary_half_extent;
    float shifted_z = p.z + pc.boundary_half_extent;
    int x = int(floor(shifted_x / pc.cell_size));
    int z = int(floor(shifted_z / pc.cell_size));
    return uvec2(
        uint(clamp(x, 0, int(pc.grid_x) - 1)),
        uint(clamp(z, 0, int(pc.grid_z) - 1))
    );
}

uint flat_cell(uvec2 c) {
    return c.y * pc.grid_x + c.x;
}

ivec2 particle_texel(uint id) {
    return ivec2(
        int(id % pc.texture_width),
        int(id / pc.texture_width)
    );
}

void write_particle_texture(uint id, vec3 p) {
    imageStore(position_image, particle_texel(id), vec4(p, 1.0));
}

vec3 consume_wake_impulse(uint id) {
    ivec3 fixed_impulse = ivec3(
        atomicExchange(wake_impulses[id].x, 0),
        atomicExchange(wake_impulses[id].y, 0),
        atomicExchange(wake_impulses[id].z, 0)
    );
    return vec3(fixed_impulse) / WAKE_IMPULSE_SCALE;
}

void add_wake_impulse(uint id, vec3 velocity_delta) {
    ivec3 fixed_impulse = ivec3(round(
        velocity_delta * WAKE_IMPULSE_SCALE
    ));
    atomicAdd(wake_impulses[id].x, fixed_impulse.x);
    atomicAdd(wake_impulses[id].y, fixed_impulse.y);
    atomicAdd(wake_impulses[id].z, fixed_impulse.z);
}

bool apply_external_commands(uint id, inout vec3 p, inout vec3 v) {
    bool touched = false;

    for (uint command_index = 0u; command_index < pc.command_count; ++command_index) {
        vec4 a = command_data[command_index * 2u];
        vec4 b = command_data[command_index * 2u + 1u];

        vec3 center = a.xyz;
        float radius = a.w;
        float mode = b.w;

        vec3 offset = p - center;
        float distance_squared = dot(offset, offset);

        if (mode < 1.5) {
            if (distance_squared >= radius * radius) {
                continue;
            }

            touched = true;
            atomicMax(grain_states[id], EXPLOSION_WAKE_LEVEL);
            grain_sleep[id] = 0u;

            float distance = sqrt(max(distance_squared, 1e-8));
            vec3 normal = distance > 1e-5
                ? offset / distance
                : vec3(0.0, 1.0, 0.0);
            float falloff = pow(
                max(0.0, 1.0 - distance / radius),
                1.20
            );
            float speed = b.x * (0.08 + 0.92 * falloff);
            v += normal * speed;
            continue;
        }

        float minimum_distance = radius + pc.grain_radius;
        if (distance_squared >= minimum_distance * minimum_distance) {
            continue;
        }

        touched = true;
        float distance = sqrt(max(distance_squared, 1e-8));
        vec3 normal = distance > 1e-4
            ? offset / distance
            : vec3(0.0, -1.0, 0.0);
        float penetration = minimum_distance - distance;

        if (mode < 2.5) {
            atomicMax(grain_states[id], BODY_WAKE_LEVEL);
            grain_sleep[id] = 0u;

            vec3 displacement = normal * penetration * 0.12;
            p += displacement;

            float closing_speed = dot(b.xyz - v, normal);
            if (closing_speed > 0.0) {
                v += normal * closing_speed * 0.12;
            }
            v += normal
                * (penetration / max(pc.dt, 1e-4))
                * 0.028;
            continue;
        }

        atomicMax(grain_states[id], FOOT_WAKE_LEVEL);
        grain_sleep[id] = 0u;

        vec3 lateral = vec3(offset.x, 0.0, offset.z);
        float lateral_length = length(lateral);
        vec3 lateral_normal;
        if (lateral_length > 1e-5) {
            lateral_normal = lateral / lateral_length;
        } else {
            vec3 travel = vec3(b.x, 0.0, b.z);
            float travel_length = length(travel);
            lateral_normal = travel_length > 1e-5
                ? -travel / travel_length
                : vec3(1.0, 0.0, 0.0);
        }

        float lateral_shift = min(penetration * 0.050, 0.0018);
        float downward_compaction = min(penetration * 0.010, 0.00055);
        vec3 displacement = lateral_normal * lateral_shift;
        displacement.y -= downward_compaction;
        p += displacement;
        previous_positions[id].xyz += displacement;
        v.xz *= 0.985;
    }

    return touched;
}

void phase_initialize(uint id) {
    uint layer_stride = pc.axis_particles * pc.axis_particles;
    uint layer = id / layer_stride;
    uint planar = id % layer_stride;
    uint x = planar % pc.axis_particles;
    uint z = planar / pc.axis_particles;

    float half_cells = float(pc.axis_particles - 1u) * 0.5;
    vec3 p = vec3(
        (float(x) - half_cells) * pc.packing_spacing,
        pc.grain_radius + float(layer) * pc.packing_spacing,
        (float(z) - half_cells) * pc.packing_spacing
    );

    positions[id] = vec4(p, 1.0);
    previous_positions[id] = vec4(p, 1.0);
    velocities[id] = vec4(0.0);
    corrections[id] = vec4(0.0);
    grain_states[id] = 0u;
    grain_sleep[id] = 0u;
    wake_impulses[id] = ivec4(0);
    write_particle_texture(id, p);
}

void phase_clear_active_count(uint id) {
    if (id == 0u) {
        active_count[0] = 0u;
    }
}

void phase_integrate(uint id) {
    vec3 p = positions[id].xyz;
    vec3 v = velocities[id].xyz;
    previous_positions[id] = vec4(p, 1.0);

    apply_external_commands(id, p, v);

    uint state = grain_states[id];
    if (state == 0u) {
        velocities[id] = vec4(0.0);
        corrections[id] = vec4(0.0);
        return;
    }

    v += consume_wake_impulse(id);
    v.y -= pc.gravity * pc.dt;
    p += v * pc.dt;

    positions[id] = vec4(p, 1.0);
    velocities[id] = vec4(v, 0.0);
}

void phase_clear_grid(uint id) {
    if (id < grid_cell_count()) {
        cell_counts[id] = 0u;
    }
}

void phase_build_grid(uint id) {
    uvec2 coords = cell_coords(positions[id].xyz);
    uint cell = flat_cell(coords);
    uint slot = atomicAdd(cell_counts[cell], 1u);
    if (slot < pc.max_cell_particles) {
        cell_particles[cell * pc.max_cell_particles + slot] = id;
    }
}

void phase_solve(uint id) {
    uint state = grain_states[id];
    if (state == 0u) {
        corrections[id] = vec4(0.0);
        return;
    }

    vec3 p = positions[id].xyz;
    vec3 p_previous = previous_positions[id].xyz;
    vec3 own_velocity = velocities[id].xyz;
    vec3 correction = vec3(0.0);
    float contact_count = 0.0;

    uvec2 own_cell = cell_coords(p);
    float diameter = pc.grain_radius * 2.0;
    float diameter_squared = diameter * diameter;

    for (int oz = -1; oz <= 1; ++oz) {
        int cz = int(own_cell.y) + oz;
        if (cz < 0 || cz >= int(pc.grid_z)) {
            continue;
        }

        for (int ox = -1; ox <= 1; ++ox) {
            int cx = int(own_cell.x) + ox;
            if (cx < 0 || cx >= int(pc.grid_x)) {
                continue;
            }

            uint cell = flat_cell(uvec2(uint(cx), uint(cz)));
            uint count = min(
                cell_counts[cell],
                pc.max_cell_particles
            );

            for (uint slot = 0u; slot < count; ++slot) {
                uint other_id = cell_particles[
                    cell * pc.max_cell_particles + slot
                ];
                if (
                    other_id == id
                    || other_id >= pc.particle_count
                ) {
                    continue;
                }

                vec3 q = positions[other_id].xyz;
                vec3 delta = q - p;
                float distance_squared = dot(delta, delta);
                if (distance_squared >= diameter_squared) {
                    continue;
                }

                contact_count += 1.0;

                float distance = sqrt(max(distance_squared, 1e-10));
                vec3 normal = distance > 1e-5
                    ? delta / distance
                    : vec3(1.0, 0.0, 0.0);
                float penetration = diameter - distance;

                uint other_state = grain_states[other_id];
                bool other_locked = other_state == 0u;

                float correction_fraction = other_locked ? 0.96 : 0.5;
                float normal_correction = penetration * correction_fraction;
                correction -= normal * normal_correction;

                vec3 other_velocity = other_locked
                    ? vec3(0.0)
                    : velocities[other_id].xyz;
                float impact_speed = max(
                    0.0,
                    dot(own_velocity - other_velocity, normal)
                );

                if (
                    other_locked
                    && state > 1u
                    && impact_speed >= WAKE_IMPACT_SPEED
                    && penetration >= WAKE_PENETRATION
                ) {
                    uint next_state = state - 1u;
                    atomicMax(grain_states[other_id], next_state);
                    grain_sleep[other_id] = 0u;

                    vec3 transferred_velocity = normal
                        * min(impact_speed * WAKE_TRANSFER, 4.5);
                    add_wake_impulse(
                        other_id,
                        transferred_velocity
                    );
                }

                vec3 q_previous = previous_positions[other_id].xyz;
                vec3 relative_displacement =
                    (p - p_previous) - (q - q_previous);
                vec3 tangent = relative_displacement
                    - normal * dot(relative_displacement, normal);
                float tangent_length = length(tangent);

                if (tangent_length > 1e-5) {
                    float static_limit =
                        pc.friction * 1.55 * penetration;

                    if (tangent_length <= static_limit) {
                        correction -= tangent
                            * (other_locked ? 0.90 : 0.5);
                    } else {
                        float dynamic_limit =
                            pc.friction * normal_correction;
                        float amount = min(
                            tangent_length
                                * (other_locked ? 0.90 : 0.5),
                            dynamic_limit
                        );
                        correction -= tangent
                            / tangent_length
                            * amount;
                    }
                }
            }
        }
    }

    float limit = pc.boundary_half_extent - pc.grain_radius;

    if (p.y < pc.grain_radius) {
        contact_count += 1.0;
        float penetration = pc.grain_radius - p.y;
        correction.y += penetration;

        vec2 lateral = p.xz - p_previous.xz;
        float lateral_length = length(lateral);
        if (lateral_length > 1e-5) {
            float static_limit =
                pc.friction * 1.55 * penetration;
            if (lateral_length <= static_limit) {
                correction.xz -= lateral;
            } else {
                float amount = min(
                    lateral_length,
                    pc.friction * penetration
                );
                correction.xz -= lateral
                    / lateral_length
                    * amount;
            }
        }
    }

    if (p.x < -limit) {
        contact_count += 1.0;
        correction.x += -limit - p.x;
    } else if (p.x > limit) {
        contact_count += 1.0;
        correction.x += limit - p.x;
    }

    if (p.z < -limit) {
        contact_count += 1.0;
        correction.z += -limit - p.z;
    } else if (p.z > limit) {
        contact_count += 1.0;
        correction.z += limit - p.z;
    }

    corrections[id] = vec4(
        correction,
        min(contact_count, MAX_DAMPING_CONTACTS)
    );
}

void phase_apply(uint id) {
    if (grain_states[id] == 0u) {
        corrections[id] = vec4(0.0);
        return;
    }

    float contacts = corrections[id].w;
    positions[id].xyz += corrections[id].xyz;
    corrections[id] = vec4(0.0, 0.0, 0.0, contacts);
}

void phase_finalize(uint id) {
    uint state = grain_states[id];
    if (state == 0u) {
        velocities[id] = vec4(0.0);
        corrections[id] = vec4(0.0);
        return;
    }

    vec3 p = positions[id].xyz;
    vec3 previous = previous_positions[id].xyz;
    vec3 old_velocity = velocities[id].xyz;
    vec3 raw_velocity =
        (p - previous) / max(pc.dt, 1e-5);

    float contacts = corrections[id].w;
    vec3 velocity = raw_velocity;

    if (contacts > 0.0) {
        vec3 correction_velocity =
            raw_velocity - old_velocity;
        velocity = old_velocity
            + correction_velocity
            * CONTACT_CORRECTION_VELOCITY_TRANSFER;

        float contact_keep = pow(
            CONTACT_KEEP_PER_CONTACT,
            min(contacts, MAX_DAMPING_CONTACTS)
        );
        velocity *= contact_keep;
    } else {
        velocity *= pc.velocity_damping;
    }

    if (
        p.y <= pc.grain_radius + 1e-4
        && old_velocity.y < 0.0
    ) {
        velocity.y = max(
            velocity.y,
            -old_velocity.y * pc.restitution
        );
    }

    float speed = length(velocity);
    bool densely_supported = contacts >= 2.0;
    bool very_slow = speed < SINGLE_SLEEP_SPEED;
    bool slow_and_supported =
        densely_supported && speed < DENSE_SLEEP_SPEED;

    uint sleep_count = grain_sleep[id];
    if (very_slow || slow_and_supported) {
        sleep_count += 1u;
    } else {
        sleep_count = 0u;
    }

    if (sleep_count >= SLEEP_STEPS) {
        grain_states[id] = 0u;
        grain_sleep[id] = 0u;
        velocity = vec3(0.0);
    } else {
        grain_sleep[id] = sleep_count;
        atomicAdd(active_count[0], 1u);
    }

    velocities[id] = vec4(velocity, 0.0);
    corrections[id] = vec4(0.0);
    write_particle_texture(id, p);
}

void phase_clear_surface(uint id) {
    if (id < pc.surface_count) {
        surface_bits[id] = 0u;
    }
}

void phase_build_surface(uint id) {
    vec3 p = positions[id].xyz;
    float bed_half =
        pc.boundary_half_extent - pc.grain_radius;
    float min_center = -bed_half;

    int x = int(round(
        (p.x - min_center) / pc.packing_spacing
    ));
    int z = int(round(
        (p.z - min_center) / pc.packing_spacing
    ));

    if (
        x < 0
        || x >= int(pc.axis_particles)
        || z < 0
        || z >= int(pc.axis_particles)
    ) {
        return;
    }

    float top = max(
        pc.grain_radius,
        p.y + pc.grain_radius
    );
    uint index =
        uint(z) * pc.axis_particles + uint(x);
    atomicMax(surface_bits[index], floatBitsToUint(top));
}

void main() {
    uint id = gl_GlobalInvocationID.x;

    if (pc.phase == 1u) {
        phase_clear_grid(id);
        return;
    }
    if (pc.phase == 7u) {
        phase_clear_surface(id);
        return;
    }
    if (pc.phase == 11u) {
        phase_clear_active_count(id);
        return;
    }

    if (id >= pc.particle_count) {
        return;
    }

    if (pc.phase == 0u) {
        phase_integrate(id);
    } else if (pc.phase == 2u) {
        phase_build_grid(id);
    } else if (pc.phase == 3u) {
        phase_solve(id);
    } else if (pc.phase == 4u) {
        phase_apply(id);
    } else if (pc.phase == 5u) {
        phase_finalize(id);
    } else if (pc.phase == 6u) {
        phase_initialize(id);
    } else if (pc.phase == 8u) {
        phase_build_surface(id);
    }
}
