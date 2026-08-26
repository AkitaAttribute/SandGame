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
layout(set = 0, binding = 9, std430) restrict buffer ChunkStates {
    uint chunk_states[];
};
layout(set = 0, binding = 10, std430) restrict buffer ChunkActivity {
    uint chunk_activity[];
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

const uint ACTIVE_STATE = 20u;
const float WAKE_IMPACT_SPEED = 1.35;
const float WAKE_PENETRATION = 0.006;
const float KEEP_ACTIVE_SPEED = 0.22;
const float CONTACT_CORRECTION_VELOCITY_TRANSFER = 0.34;
const float CONTACT_KEEP_PER_CONTACT = 0.82;
const float DENSE_SETTLE_SPEED = 0.26;
const float SINGLE_CONTACT_SETTLE_SPEED = 0.085;
const float MAX_DAMPING_CONTACTS = 6.0;

uint region_grid() {
    return pc.axis_particles / pc.region_size;
}

uint chunk_count() {
    uint n = region_grid();
    return n * n;
}

uint grid_cell_count() {
    return pc.grid_x * pc.grid_z;
}

uint particle_layer_stride() {
    return pc.axis_particles * pc.axis_particles;
}

uvec2 original_planar_coords(uint id) {
    uint planar = id % particle_layer_stride();
    return uvec2(planar % pc.axis_particles, planar / pc.axis_particles);
}

uvec2 home_chunk_coords(uint id) {
    uvec2 planar = original_planar_coords(id);
    return uvec2(planar.x / pc.region_size, planar.y / pc.region_size);
}

uint flat_chunk(uvec2 c) {
    return c.y * region_grid() + c.x;
}

uint home_chunk(uint id) {
    return flat_chunk(home_chunk_coords(id));
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

bool apply_external_commands(uint id, inout vec3 p, inout vec3 v) {
    bool touched = false;
    uint chunk = home_chunk(id);

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
            atomicMax(chunk_states[chunk], ACTIVE_STATE);

            float distance = sqrt(max(distance_squared, 1e-8));
            vec3 normal = distance > 1e-5
                ? offset / distance
                : vec3(0.0, 1.0, 0.0);
            float falloff = pow(max(0.0, 1.0 - distance / radius), 1.20);
            float speed = b.x * (0.08 + 0.92 * falloff);
            v += normal * speed;
            continue;
        }

        float minimum_distance = radius + pc.grain_radius;
        if (distance_squared >= minimum_distance * minimum_distance) {
            continue;
        }

        touched = true;
        atomicMax(chunk_states[chunk], ACTIVE_STATE);

        float distance = sqrt(max(distance_squared, 1e-8));
        vec3 normal = distance > 1e-4
            ? offset / distance
            : vec3(0.0, -1.0, 0.0);
        float penetration = minimum_distance - distance;

        if (mode < 2.5) {
            p += normal * penetration * 0.20;
            float closing_speed = dot(b.xyz - v, normal);
            if (closing_speed > 0.0) {
                v += normal * closing_speed * 0.20;
            }
            v += normal * (penetration / max(pc.dt, 1e-4)) * 0.045;
            continue;
        }

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

        float lateral_shift = min(penetration * 0.060, 0.0025);
        float downward_compaction = min(penetration * 0.014, 0.0008);
        vec3 displacement = lateral_normal * lateral_shift;
        displacement.y -= downward_compaction;
        p += displacement;
        previous_positions[id].xyz += displacement;
        v.xz *= 0.975;
    }

    return touched;
}

void phase_initialize(uint id) {
    uint layer_stride = particle_layer_stride();
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
    write_particle_texture(id, p);
}

void phase_update_chunks(uint id) {
    if (id >= chunk_count()) {
        return;
    }

    uint state = chunk_states[id];
    float activity = uintBitsToFloat(chunk_activity[id]);

    if (state >= 2u) {
        if (activity >= KEEP_ACTIVE_SPEED) {
            state = ACTIVE_STATE;
        } else if (state > 2u) {
            state -= 1u;
        } else {
            state = 1u;
        }
    } else if (state == 1u) {
        state = 0u;
    }

    chunk_states[id] = state;
    chunk_activity[id] = 0u;
}

void phase_expand_guards(uint id) {
    if (id >= chunk_count() || chunk_states[id] < 2u) {
        return;
    }

    uint n = region_grid();
    uint cx = id % n;
    uint cz = id / n;

    for (int oz = -1; oz <= 1; ++oz) {
        int z = int(cz) + oz;
        if (z < 0 || z >= int(n)) {
            continue;
        }
        for (int ox = -1; ox <= 1; ++ox) {
            int x = int(cx) + ox;
            if (x < 0 || x >= int(n) || (ox == 0 && oz == 0)) {
                continue;
            }
            uint neighbor = uint(z) * n + uint(x);
            atomicMax(chunk_states[neighbor], 1u);
        }
    }
}

void phase_integrate(uint id) {
    vec3 p = positions[id].xyz;
    vec3 v = velocities[id].xyz;
    previous_positions[id] = vec4(p, 1.0);

    bool touched = apply_external_commands(id, p, v);
    uint state = chunk_states[home_chunk(id)];

    if (state < 2u && !touched) {
        velocities[id] = vec4(0.0);
        corrections[id] = vec4(0.0);
        return;
    }

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
    uint state = chunk_states[home_chunk(id)];
    if (state == 0u) {
        return;
    }

    uvec2 coords = cell_coords(positions[id].xyz);
    uint cell = flat_cell(coords);
    uint slot = atomicAdd(cell_counts[cell], 1u);
    if (slot < pc.max_cell_particles) {
        cell_particles[cell * pc.max_cell_particles + slot] = id;
    }
}

void phase_solve(uint id) {
    uint own_chunk = home_chunk(id);
    if (chunk_states[own_chunk] < 2u) {
        corrections[id] = vec4(0.0);
        return;
    }

    vec3 p = positions[id].xyz;
    vec3 p_previous = previous_positions[id].xyz;
    vec3 correction = vec3(0.0);
    float contact_count = 0.0;
    uvec2 own_cell = cell_coords(p);
    float diameter = pc.grain_radius * 2.0;
    float diameter_squared = diameter * diameter;
    vec3 own_motion = (p - p_previous) / max(pc.dt, 1e-5);

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
            uint count = min(cell_counts[cell], pc.max_cell_particles);
            for (uint slot = 0u; slot < count; ++slot) {
                uint other_id = cell_particles[cell * pc.max_cell_particles + slot];
                if (other_id == id || other_id >= pc.particle_count) {
                    continue;
                }

                vec3 q = positions[other_id].xyz;
                vec3 delta = q - p;
                float distance_squared = dot(delta, delta);
                if (distance_squared >= diameter_squared) {
                    continue;
                }

                uint other_chunk = home_chunk(other_id);
                uint other_state = chunk_states[other_chunk];
                if (other_state == 0u) {
                    continue;
                }

                contact_count += 1.0;
                float distance = sqrt(max(distance_squared, 1e-10));
                vec3 normal = distance > 1e-5
                    ? delta / distance
                    : vec3(1.0, 0.0, 0.0);
                float penetration = diameter - distance;

                bool other_is_guard = other_state == 1u;
                float normal_correction = penetration * (other_is_guard ? 1.0 : 0.5);
                correction -= normal * normal_correction;

                if (other_is_guard) {
                    float impact_speed = max(0.0, dot(own_motion, normal));
                    if (
                        impact_speed >= WAKE_IMPACT_SPEED
                        && penetration >= WAKE_PENETRATION
                    ) {
                        atomicMax(chunk_states[other_chunk], ACTIVE_STATE);
                    }
                }

                vec3 q_previous = previous_positions[other_id].xyz;
                vec3 relative_displacement =
                    (p - p_previous) - (q - q_previous);
                vec3 tangent = relative_displacement
                    - normal * dot(relative_displacement, normal);
                float tangent_length = length(tangent);

                if (tangent_length > 1e-5) {
                    float static_limit = pc.friction * 1.45 * penetration;
                    if (tangent_length <= static_limit) {
                        correction -= tangent * (other_is_guard ? 0.85 : 0.5);
                    } else {
                        float dynamic_limit = pc.friction * normal_correction;
                        float amount = min(
                            tangent_length * (other_is_guard ? 0.85 : 0.5),
                            dynamic_limit
                        );
                        correction -= tangent / tangent_length * amount;
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
            float static_limit = pc.friction * 1.45 * penetration;
            if (lateral_length <= static_limit) {
                correction.xz -= lateral;
            } else {
                float amount = min(lateral_length, pc.friction * penetration);
                correction.xz -= lateral / lateral_length * amount;
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

    corrections[id] = vec4(correction, min(contact_count, MAX_DAMPING_CONTACTS));
}

void phase_apply(uint id) {
    if (chunk_states[home_chunk(id)] < 2u) {
        corrections[id] = vec4(0.0);
        return;
    }

    float contacts = corrections[id].w;
    positions[id].xyz += corrections[id].xyz;
    corrections[id] = vec4(0.0, 0.0, 0.0, contacts);
}

void phase_finalize(uint id) {
    uint chunk = home_chunk(id);
    if (chunk_states[chunk] < 2u) {
        velocities[id] = vec4(0.0);
        corrections[id] = vec4(0.0);
        return;
    }

    vec3 p = positions[id].xyz;
    vec3 previous = previous_positions[id].xyz;
    vec3 old_velocity = velocities[id].xyz;
    vec3 raw_velocity = (p - previous) / max(pc.dt, 1e-5);
    float contacts = corrections[id].w;
    vec3 velocity = raw_velocity;

    if (contacts > 0.0) {
        vec3 correction_velocity = raw_velocity - old_velocity;
        velocity = old_velocity
            + correction_velocity * CONTACT_CORRECTION_VELOCITY_TRANSFER;

        float contact_keep = pow(
            CONTACT_KEEP_PER_CONTACT,
            min(contacts, MAX_DAMPING_CONTACTS)
        );
        velocity *= contact_keep;

        float speed_squared = dot(velocity, velocity);
        float dense_limit_squared = DENSE_SETTLE_SPEED * DENSE_SETTLE_SPEED;
        float single_limit_squared = SINGLE_CONTACT_SETTLE_SPEED * SINGLE_CONTACT_SETTLE_SPEED;
        if (
            (contacts >= 2.0 && speed_squared < dense_limit_squared)
            || speed_squared < single_limit_squared
        ) {
            velocity = vec3(0.0);
        }
    } else {
        velocity *= pc.velocity_damping;
    }

    if (p.y <= pc.grain_radius + 1e-4 && old_velocity.y < 0.0) {
        velocity.y = max(velocity.y, -old_velocity.y * pc.restitution);
    }

    float speed = length(velocity);
    atomicMax(chunk_activity[chunk], floatBitsToUint(speed));

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
    float bed_half = pc.boundary_half_extent - pc.grain_radius;
    float min_center = -bed_half;
    int x = int(round((p.x - min_center) / pc.packing_spacing));
    int z = int(round((p.z - min_center) / pc.packing_spacing));
    if (
        x < 0 || x >= int(pc.axis_particles)
        || z < 0 || z >= int(pc.axis_particles)
    ) {
        return;
    }

    float top = max(pc.grain_radius, p.y + pc.grain_radius);
    uint index = uint(z) * pc.axis_particles + uint(x);
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
    if (pc.phase == 9u) {
        phase_update_chunks(id);
        return;
    }
    if (pc.phase == 10u) {
        phase_expand_guards(id);
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
