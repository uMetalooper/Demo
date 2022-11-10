#include <metal_stdlib>
using namespace metal;


// Vertex input/output structure for passing results from vertex shader to fragment shader
struct VertexIO
{
    float4 position [[position]];
    float2 textureCoord [[user(texturecoord)]];
};

// Vertex shader for a textured quad
vertex VertexIO vertexEffect(const device packed_float4 *pPosition  [[ buffer(0) ]],
                             const device packed_float2 *pTexCoords [[ buffer(1) ]],
                             uint                  vid        [[ vertex_id ]])
{
    VertexIO outVertex;
    
    outVertex.position = pPosition[vid];
    outVertex.textureCoord = pTexCoords[vid];
    
    return outVertex;
}

// Fragment shader for a textured quad
fragment half4 fragmentEffect(VertexIO         inputFragment [[ stage_in ]],
                              texture2d<half> inputTexture  [[ texture(0) ]],
                              texture2d<half> inputBlurredTexture  [[ texture(1) ]],
                              texture2d<half> maskTexture   [[ texture(2) ]],
                              sampler         samplr        [[ sampler(0) ]])
{
    half4 bgColor = inputTexture.sample(samplr, inputFragment.textureCoord);
    half4 blurredColor = inputBlurredTexture.sample(samplr, inputFragment.textureCoord);
    half4 maskColor = maskTexture.sample(samplr, inputFragment.textureCoord);

    half4 brightColor = clamp(blurredColor + 0.1, 0.0, 1.0);

    return half4(mix(bgColor.rgb, brightColor.rgb, 1-maskColor.r), bgColor.a);
}
