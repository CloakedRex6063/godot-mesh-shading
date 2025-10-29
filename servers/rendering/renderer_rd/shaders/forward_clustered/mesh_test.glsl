#[mesh]

#version 450
#include "mesh_test_inc.glsl"

layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;
layout(triangles, max_vertices = 64, max_primitives = 128) out;

struct OutVertex
{
    vec3 position;
    vec3 normal;
    vec2 uv;
    vec3 tangent;
    vec3 binormal;
};

layout(location = 0) out OutVertex out_verts[];

vec3 unpack_vertex(uint vertex_index)
{
    uint src_offset = vertex_index * vertex_stride();
    vec3 vertex = uintBitsToFloat(uvec3(
        draw_call.vertex_buffer.vertices[src_offset + 0],
        draw_call.vertex_buffer.vertices[src_offset + 1],
        draw_call.vertex_buffer.vertices[src_offset + 2]
    ));
    vertex = vertex * instances.data[draw_call.instance_index].compressed_aabb_size_pad.xyz + instances.data[draw_call.instance_index].compressed_aabb_position_pad.xyz;
    return vertex;
}

vec2 unpack_uv(uint vertex_index)
{
    uint uv_stride = uv_stride();
    uint packed_uv = draw_call.attrib_buffer.attribs[vertex_index * uv_stride];
    uint packed_uv2 = draw_call.attrib_buffer.attribs[vertex_index * uv_stride + 1];
    vec2 uv = mix(unpackHalf2x16(packed_uv),
                   vec2(uintBitsToFloat(packed_uv), uintBitsToFloat(packed_uv2)),
                   float(uv_stride - 1));
    return uv;
}

void unpack_normals(uint vertex_index, out vec3 normal, out vec3 tangent, out vec3 binormal)
{
    uint src_normal = vertex_count() * vertex_stride() + vertex_index * normal_tangent_stride();
    if (normal_tangent_stride() > 0) {
        normal = decode_uint_oct_to_norm(draw_call.vertex_buffer.vertices[src_normal]);
        src_normal++;
    }
	if (normal_tangent_stride() > 1) 
    {
        vec4 decoded = decode_uint_oct_to_tang(draw_call.vertex_buffer.vertices[src_normal]);
        tangent = decoded.xyz;
        binormal = cross(normal, tangent) * decoded.w;
    }
}

void main()
{
    uint lid = gl_LocalInvocationID.x;
    uint gid = gl_WorkGroupID.x;

    Meshlet meshlet = draw_call.meshlet_buffer.meshlets[gid];
    SetMeshOutputsEXT(meshlet.vertex_count, meshlet.triangle_count);

    if(lid < meshlet.triangle_count)
    {
        uint packed = draw_call.meshlet_triangle_buffer.indices[meshlet.triangle_offset + lid];
        uint idx0 = (packed >> 0) & 0xFF;
        uint idx1 = (packed >> 8) & 0xFF;
        uint idx2 = (packed >> 16) & 0xFF;
        gl_PrimitiveTriangleIndicesEXT[lid] = uvec3(idx0, idx1, idx2);
    }

    if(lid < meshlet.vertex_count)
    {
        uint vertex_index = meshlet.vertex_offset + lid;
        vertex_index = draw_call.meshlet_vertex_buffer.vertices[vertex_index];
        vec3 vertex = unpack_vertex(vertex_index);
        vec2 uv = unpack_uv(vertex_index);
        vec3 normal, tangent, binormal;
        unpack_normals(vertex_index, normal, tangent, binormal);

        SceneData scene_data = scene_data_block.data;
        mat4 model_matrix = instances.data[draw_call.instance_index].transform;
        vec4 position = scene_data.projection_matrix * scene_data.view_matrix * model_matrix * vec4(vertex, 1.0);

        out_verts[lid].position = (model_matrix * vec4(vertex, 1.0)).xyz;
        out_verts[lid].normal = vec3(float((gid + 1) & 1), float((gid + 1) & 3) / 4, float((gid + 1) & 7) / 8);
        out_verts[lid].uv = uv;
        out_verts[lid].tangent = tangent;
        out_verts[lid].binormal = binormal;

        gl_MeshVerticesEXT[lid].gl_Position = position;
    }
}

#[fragment]

#version 450

struct Vertex
{
    vec3 position;
    vec3 normal;
    vec2 uv;
    vec3 tangent;
    vec3 binormal;
};

layout(location = 0) in Vertex vertex;
layout(location = 0) out vec4 out_frag_color;

void main()
{
    out_frag_color = vec4(vertex.normal, 1.0);
}


//#[mesh]
//
//#version 450
//#include "mesh_test_inc.glsl"
//
//layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
//layout(triangles, max_vertices = 3, max_primitives = 1) out;
//
//layout(location = 0) out VertexOutput
//{
//mat4 viewProj;
//vec4 color;
//} vertexOutput[];
//
//const vec4[3] positions = {
//vec4( 0.0, -1.0, 0.0, 1.0),
//vec4(-1.0,  1.0, 0.0, 1.0),
//vec4( 1.0,  1.0, 0.0, 1.0)
//};
//
//const vec4[3] colors = {
//vec4(0.0, 1.0, 0.0, 1.0),
//vec4(0.0, 0.0, 1.0, 1.0),
//vec4(1.0, 0.0, 0.0, 1.0)
//};
//
//void main()
//{
//
//vec4 offset = vec4(0.0, 0.0, 0.0, 0.0);
//
//SetMeshOutputsEXT(3, 1);
//mat4 model_matrix = mat4(1.0); //instances.data[draw_call.instance_index].transform;
//SceneData scene_data = scene_data_block.data;
//mat4 mvp = scene_data.projection_matrix * scene_data.view_matrix * model_matrix;
//gl_MeshVerticesEXT[0].gl_Position = mvp * (positions[0] + offset);
//gl_MeshVerticesEXT[1].gl_Position = mvp * (positions[1] + offset);
//gl_MeshVerticesEXT[2].gl_Position = mvp * (positions[2] + offset);
//vertexOutput[0].color = colors[0];
//vertexOutput[1].color = colors[1];
//vertexOutput[2].color = colors[2];
//gl_PrimitiveTriangleIndicesEXT[gl_LocalInvocationIndex] =  uvec3(0, 1, 2);
//        
//vertexOutput[0].viewProj = scene_data.projection_matrix * scene_data.view_matrix;
//vertexOutput[1].viewProj = scene_data.projection_matrix * scene_data.view_matrix;
//vertexOutput[2].viewProj = scene_data.projection_matrix * scene_data.view_matrix;
//
//}
//
//#[fragment]
//
//#version 450
//
//layout (location = 0) in VertexInput {
//mat4 viewproj;
//vec4 color;
//} vertexInput;
//
//layout(location = 0) out vec4 outFragColor;
//
//
//void main()
//{
//outFragColor = vertexInput.color;
//}