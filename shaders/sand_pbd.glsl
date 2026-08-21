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

layout(push_constant, std430) uniform Params {
    uint phase;
    uint particle_count;
    uint grid_x;
    uint grid_y;

    uint grid_z;
    uint max_cell_particles;
    uint command_count;
    uint iteration;

    float dt;
    float grain_radius;
    float boundary_half_extent;
    float cell_size;

    float gravity;
    float friction;
    float restitution;
    float velocity_damping;
} pc;

uint grid_cell_count() {
    return pc.grid_x * pc.grid_y * pc.grid_z;
}

uvec3 cell_coords(vec3 p) {
    float shifted_x = p.x + pc.boundary_half_extent;
    float shifted_z = p.z + pc.boundary_half_extent;

    int x = int(floor(shifted_x / pc.cell_size));
    int y = int(floor(max(p.y, 0.0) / pc.cell_size));
    int z = int(floor(shifted_z / pc.cell_size));

    return uvec3(
        uint(clamp(x, 0, int(pc.grid_x) - 1)),
        uint(clamp(y, 0, int(pc.grid_y) - 1)),
        uint(clamp(z, 0, int(pc.grid_z) - 1))
    );
}

uint flat_cell(uvec3 c) {
    return (c.y * pc.grid_z + c.z) * pc.grid_x + c.x;
}

void apply_external_commands(uint id, inout vec3 p, inout vec3 v) {
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

            float distance = sqrt(max(distance_squared, 1e-8));
            vec3 normal = offset / distance;
            float falloff = pow(max(0.0, 1.0 - distance / radius), 1.25);
            float speed = b.x * (0.10 + 0.90 * falloff);
            v += normal * speed;
        } else {
            float minimum_distance = radius + pc.grain_radius;
            if (distance_squared >= minimum_distance * minimum_distance) {
                continue;
            }

            float distance = sqrt(max(distance_squared, 1e-8));
            vec3 normal = distance > 1e-4 ? offset / distance : vec3(0.0, -1.0, 0.0);
            float penetration = minimum_distance - distance;

            p += normal * penetration * 0.72;

            float closing_speed = dot(b.xyz - v, normal);
            if (closing_speed > 0.0) {
                v += normal * closing_speed * 0.62;
            }

            v += normal * (penetration / max(pc.dt, 1e-4)) * 0.20;
        }
    }
}

void phase_integrate(uint id) {
    vec3 p = positions[id].xyz;
    vec3 v = velocities[id].xyz;

    previous_positions[id] = vec4(p, 1.0);

    v.y -= pc.gravity * pc.dt;
    apply_external_commands(id, p, v);
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
    uvec3 coords = cell_coords(positions[id].xyz);
    uint cell = flat_cell(coords);
    uint slot = atomicAdd(cell_counts[cell], 1u);

    if (slot < pc.max_cell_particles) {
        cell_particles[cell * pc.max_cell_particles + slot] = id;
    }
}

void phase_solve(uint id) {
    vec3 p = positions[id].xyz;
    vec3 p_previous = previous_positions[id].xyz;
    vec3 correction = vec3(0.0);

    uvec3 own_cell = cell_coords(p);
    float diameter = pc.grain_radius * 2.0;
    float diameter_squared = diameter * diameter;

    for (int oy = -1; oy <= 1; ++oy) {
        int cy = int(own_cell.y) + oy;
        if (cy < 0 || cy >= int(pc.grid_y)) {
            continue;
        }

        for (int oz = -1; oz <= 1; ++oz) {
            int cz = int(own_cell.z) + oz;
            if (cz < 0 || cz >= int(pc.grid_z)) {
                continue;
            }

            for (int ox = -1; ox <= 1; ++ox) {
                int cx = int(own_cell.x) + ox;
                if (cx < 0 || cx >= int(pc.grid_x)) {
                    continue;
                }

                uint cell = flat_cell(uvec3(uint(cx), uint(cy), uint(cz)));
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

                    float distance = sqrt(max(distance_squared, 1e-10));
                    vec3 normal = distance > 1e-5
                        ? delta / distance
                        : vec3(1.0, 0.0, 0.0);

                    float penetration = diameter - distance;
                    correction -= normal * penetration * 0.5;

                    vec3 q_previous = previous_positions[other_id].xyz;
                    vec3 relative_displacement =
                        (p - p_previous) - (q - q_previous);
                    vec3 tangent =
                        relative_displacement
                        - normal * dot(relative_displacement, normal);
                    float tangent_length = length(tangent);

                    if (tangent_length > 1e-5) {
                        float max_friction = pc.friction * penetration * 0.5;
                        float friction_amount = min(tangent_length * 0.5, max_friction);
                        correction -= tangent / tangent_length * friction_amount;
                    }
                }
            }
        }
    }

    float limit = pc.boundary_half_extent - pc.grain_radius;

    if (p.y < pc.grain_radius) {
        float penetration = pc.grain_radius - p.y;
        correction.y += penetration;

        vec2 lateral = p.xz - p_previous.xz;
        float lateral_length = length(lateral);
        if (lateral_length > 1e-5) {
            float max_friction = pc.friction * penetration;
            float amount = min(lateral_length, max_friction);
            correction.xz -= lateral / lateral_length * amount;
        }
    }

    if (p.x < -limit) {
        correction.x += -limit - p.x;
    } else if (p.x > limit) {
        correction.x += limit - p.x;
    }

    if (p.z < -limit) {
        correction.z += -limit - p.z;
    } else if (p.z > limit) {
        correction.z += limit - p.z;
    }

    corrections[id] = vec4(correction, 0.0);
}

void phase_apply(uint id) {
    positions[id].xyz += corrections[id].xyz;
    corrections[id] = vec4(0.0);
}

void phase_finalize(uint id) {
    vec3 p = positions[id].xyz;
    vec3 previous = previous_positions[id].xyz;
    vec3 old_velocity = velocities[id].xyz;
    vec3 velocity = (p - previous) / max(pc.dt, 1e-5);

    if (p.y <= pc.grain_radius + 1e-4 && old_velocity.y < 0.0) {
        velocity.y = max(velocity.y, -old_velocity.y * pc.restitution);
    }

    velocity *= pc.velocity_damping;

    if (
        p.y <= pc.grain_radius + 0.002
        && dot(velocity, velocity) < 0.0009
    ) {
        velocity = vec3(0.0);
    }

    velocities[id] = vec4(velocity, 0.0);
}

void main() {
    uint id = gl_GlobalInvocationID.x;

    if (pc.phase == 1u) {
        phase_clear_grid(id);
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
    }
}
