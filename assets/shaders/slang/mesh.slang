struct VertexInput {
    float3 position;
    float3 normal;
    float2 uv0;
}

struct VertexOutput {
    float4 position : SV_Position;
    float2 uv0;
};

struct VertexData {
    float4x4 mvp_matrix;
};

layout(set = 1, binding = 0) ConstantBuffer<VertexData> vert_uniform;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
    VertexOutput output;

    output.position = mul(vert_uniform.mvp_matrix, float4(input.position, 1.0));
    output.uv0 = input.uv0;

    return output;
}

struct FragOutput {
    float4 color : SV_Target;
}

// struct FragData {
//     float4 color;
// };
// layout(set = 3, binding = 0) ConstantBuffer<FragData> frag_uniform;

[shader("fragment")]
FragOutput fragmentMain(VertexOutput vertex)  {
    FragOutput output;

    output.color = float4(vertex.uv0, 0, 1);

    return output;
}
