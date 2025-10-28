#extension GL_EXT_mesh_shader : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference2 : require

#define MAX_VIEWS 1

struct SceneData {
    mat4 projection_matrix;
    mat4 inv_projection_matrix;
    mat4 inv_view_matrix;
    mat4 view_matrix;

    // only used for multiview
    mat4 projection_matrix_view[MAX_VIEWS];
    mat4 inv_projection_matrix_view[MAX_VIEWS];
    vec4 eye_offset[MAX_VIEWS];

    // Used for billboards to cast correct shadows.
    mat4 main_cam_inv_view_matrix;

    vec2 viewport_size;
    vec2 screen_pixel_size;

    // Use vec4s because std140 doesn't play nice with vec2s, z and w are wasted.
    vec4 directional_penumbra_shadow_kernel[32];
    vec4 directional_soft_shadow_kernel[32];
    vec4 penumbra_shadow_kernel[32];
    vec4 soft_shadow_kernel[32];

    vec2 shadow_atlas_pixel_size;
    vec2 directional_shadow_pixel_size;

    uint directional_light_count;
    float dual_paraboloid_side;
    float z_far;
    float z_near;

    float roughness_limiter_amount;
    float roughness_limiter_limit;
    float opaque_prepass_threshold;
    uint flags;

    mat3 radiance_inverse_xform;

    vec4 ambient_light_color_energy;

    float ambient_color_sky_mix;
    float fog_density;
    float fog_height;
    float fog_height_density;

    float fog_depth_curve;
    float fog_depth_begin;
    float fog_depth_end;
    float fog_sun_scatter;

    vec3 fog_light_color;
    float fog_aerial_perspective;

    float time;
    float taa_frame_count;
    vec2 taa_jitter;

    float emissive_exposure_normalization;
    float IBL_exposure_normalization;
    uint camera_visible_layers;
    float pass_alpha_multiplier;
};

layout(set = 1, binding = 0, std140) uniform SceneDataBlock {
    SceneData data;
    SceneData prev_data;
}
scene_data_block;

struct InstanceData {
    mat4 transform;
    mat4 prev_transform;
    uint flags;
    uint instance_uniforms_ofs; //base offset in global buffer for instance variables
    uint gi_offset; //GI information when using lightmapping (VCT or lightmap index)
    uint layer_mask;
    vec4 lightmap_uv_scale;
    vec4 compressed_aabb_position_pad; // Only .xyz is used. .w is padding.
    vec4 compressed_aabb_size_pad; // Only .xyz is used. .w is padding.
    vec4 uv_scale;
};

layout(set = 1, binding = 2, std430) buffer restrict readonly InstanceDataBuffer {
    InstanceData data[];
}
instances;

layout(buffer_reference, std430, buffer_reference_align = 4) buffer VertexBuffer
{
    uint vertices[];
};

layout(buffer_reference, std430, buffer_reference_align = 4) buffer MeshletTriangleBuffer
{
    uint indices[];
};

layout(buffer_reference, std430, buffer_reference_align = 4) buffer MeshletVertexBuffer
{
    uint vertices[];
};

struct Meshlet
{
    uint vertex_offset;
    uint triangle_offset;
    uint vertex_count;
    uint triangle_count;
};

layout(buffer_reference, std430, buffer_reference_align = 4) buffer MeshletBuffer
{
    Meshlet meshlets[];
};

layout(buffer_reference, std430, buffer_reference_align = 4) buffer AttribBuffer
{
    uint attribs[];
};

layout(push_constant, std430) uniform DrawCall {
    VertexBuffer vertex_buffer;
    MeshletVertexBuffer meshlet_vertex_buffer;

    MeshletTriangleBuffer meshlet_triangle_buffer;
    MeshletBuffer meshlet_buffer;

    AttribBuffer attrib_buffer;
    uint vertex_count;
    uint packed_attrib;

    uint padding;
    uint instance_index;
    uvec2 padding2;
} draw_call;

uint color_stride()
{
    return draw_call.packed_attrib & 0xFu;
}

uint uv_stride()
{
    return ((draw_call.packed_attrib >> 4u)) & 0xFu;
}

uint uv2_stride()
{
    return ((draw_call.packed_attrib >> 8u)) & 0xFu;
}

uint skin_offset()
{
    return ((draw_call.packed_attrib >> 12u)) & 0xFu;
}

uint skin_weight_offset()
{
    return ((draw_call.packed_attrib >> 16u)) & 0xFu;
}

uint vertex_stride()
{
    return ((draw_call.packed_attrib >> 20u)) & 0xFu;
}

uint normal_tangent_stride()
{
    return ((draw_call.packed_attrib >> 24u)) & 0xFu;
}

uint vertex_count()
{
    return draw_call.vertex_count;
}

vec3 oct_to_vec3(vec2 e) {
    vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    float t = max(-v.z, 0.0);
    v.xy += t * -sign(v.xy);
    return normalize(v);
}

vec2 uint_to_vec2(uint base) {
    uvec2 decode = (uvec2(base) >> uvec2(0, 16)) & uvec2(0xFFFF, 0xFFFF);
    return vec2(decode) / vec2(65535.0, 65535.0) * 2.0 - 1.0;
}

uint vec2_to_uint(vec2 base) {
    uvec2 enc = uvec2(clamp(ivec2(base * vec2(65535, 65535)), ivec2(0), ivec2(0xFFFF, 0xFFFF))) << uvec2(0, 16);
    return enc.x | enc.y;
}

vec3 decode_uint_oct_to_norm(uint base) {
    return oct_to_vec3(uint_to_vec2(base));
}

vec4 decode_uint_oct_to_tang(uint base) {
    vec2 oct_sign_encoded = uint_to_vec2(base);
    // Binormal sign encoded in y component
    vec2 oct = vec2(oct_sign_encoded.x, abs(oct_sign_encoded.y) * 2.0 - 1.0);
    return vec4(oct_to_vec3(oct), sign(oct_sign_encoded.y));
}