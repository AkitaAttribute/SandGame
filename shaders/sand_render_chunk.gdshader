shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D position_texture : filter_nearest, repeat_disable;
uniform int position_texture_width = 1024;
uniform int axis_particles = 400;
uniform int region_size = 16;
uniform int region_x = 0;
uniform int region_z = 0;

varying vec3 grain_color;

void vertex() {
    int local_layer_stride = region_size * region_size;
    int layer = INSTANCE_ID / local_layer_stride;
    int local_planar = INSTANCE_ID % local_layer_stride;
    int local_x = local_planar % region_size;
    int local_z = local_planar / region_size;

    int x = region_x * region_size + local_x;
    int z = region_z * region_size + local_z;
    int global_id = layer * axis_particles * axis_particles
        + z * axis_particles
        + x;

    ivec2 texel = ivec2(
        global_id % position_texture_width,
        global_id / position_texture_width
    );
    vec3 particle_position = texelFetch(position_texture, texel, 0).xyz;
    VERTEX += particle_position;

    int color_index = (region_x % 2) + (region_z % 2) * 2;
    if (color_index == 0) {
        grain_color = vec3(0.86, 0.18, 0.15);
    } else if (color_index == 1) {
        grain_color = vec3(0.15, 0.38, 0.92);
    } else if (color_index == 2) {
        grain_color = vec3(0.95, 0.79, 0.14);
    } else {
        grain_color = vec3(0.18, 0.72, 0.31);
    }
}

void fragment() {
    ALBEDO = grain_color;
    ROUGHNESS = 0.97;
    METALLIC = 0.0;
}
