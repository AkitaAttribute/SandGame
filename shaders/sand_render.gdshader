shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D position_texture : filter_nearest, repeat_disable;
uniform int position_texture_width = 1024;
uniform int axis_particles = 400;
uniform int region_size = 16;

varying vec3 grain_color;

void vertex() {
    int id = INSTANCE_ID;
    ivec2 texel = ivec2(
        id % position_texture_width,
        id / position_texture_width
    );
    vec3 particle_position = texelFetch(position_texture, texel, 0).xyz;
    VERTEX += particle_position;

    int layer_stride = axis_particles * axis_particles;
    int planar_id = id % layer_stride;
    int x = planar_id % axis_particles;
    int z = planar_id / axis_particles;
    int region_x = x / region_size;
    int region_z = z / region_size;
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
