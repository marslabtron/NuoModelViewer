

#include "ShadersCommon.h"

using namespace metal;

struct Vertex
{
    float4 position;
    float4 normal;
};

struct ProjectedVertex
{
    float4 position [[position]];
    float3 eye;
    float3 normal;
    
    float4 shadowPosition0;
    float4 shadowPosition1;
};


ProjectedVertex vertex_project_common(device Vertex *vertices,
                                      constant NuoUniforms &uniforms,
                                      constant NuoMeshUniforms &meshUniform,
                                      uint vid [[vertex_id]]);

float3 fresnel_schlick(float3 specularColor, float3 lightVector, float3 halfway);



/**
 *  shader that generate shadow-map texture from the light view point.
 *  no fragement shader needed.
 */

vertex PositionSimple vertex_shadow(device Vertex *vertices [[buffer(0)]],
                                    constant NuoUniforms &uniforms [[buffer(1)]],
                                    constant NuoMeshUniforms &meshUniform [[buffer(2)]],
                                    uint vid [[vertex_id]])
{
    PositionSimple outShadow;
    outShadow.position = uniforms.viewProjectionMatrix *
                         meshUniform.transform * vertices[vid].position;
    return outShadow;
}



/**
 *  shaders that generate phong result without shadow casting,
 *  used for simple annotation.
 */

vertex ProjectedVertex vertex_project(device Vertex *vertices [[buffer(0)]],
                                      constant NuoUniforms &uniforms [[buffer(1)]],
                                      constant NuoMeshUniforms &meshUniform [[buffer(2)]],
                                      uint vid [[vertex_id]])
{
    return vertex_project_common(vertices, uniforms, meshUniform, vid);
}



fragment float4 fragment_light(ProjectedVertex vert [[stage_in]],
                               constant LightUniform &lightUniform [[buffer(0)]],
                               constant ModelCharacterUniforms &modelCharacterUniforms [[buffer(1)]],
                               sampler samplr [[sampler(0)]])
{
    float3 normal = normalize(vert.normal);
    float3 ambientTerm = lightUniform.ambientDensity * material.ambientColor;
    float3 colorForLights = 0.0;
    
    for (unsigned i = 0; i < 4; ++i)
    {
        float diffuseIntensity = saturate(dot(normal, normalize(lightUniform.direction[i].xyz)));
        float3 diffuseTerm = material.diffuseColor * diffuseIntensity;
        
        float3 specularTerm(0);
        if (diffuseIntensity > 0)
        {
            float3 eyeDirection = normalize(vert.eye);
            float3 halfway = normalize(normalize(lightUniform.direction[i].xyz) + eyeDirection);
            float specularFactor = pow(saturate(dot(normal, halfway)), material.specularPower);
            specularTerm = material.specularColor * specularFactor;
        }
        
        colorForLights += diffuseTerm * lightUniform.density[i] + specularTerm * lightUniform.spacular[i];
    }
    
    return float4(ambientTerm + colorForLights, modelCharacterUniforms.opacity);
}



/**
 *  shaders that generate phong result wit shadow casting,
 */

vertex ProjectedVertex vertex_project_shadow(device Vertex *vertices [[buffer(0)]],
                                             constant NuoUniforms &uniforms [[buffer(1)]],
                                             constant LightVertexUniforms &lightCast [[buffer(2)]],
                                             constant NuoMeshUniforms &meshUniform [[buffer(3)]],
                                             uint vid [[vertex_id]])
{
    ProjectedVertex outVert = vertex_project_common(vertices, uniforms, meshUniform, vid);
    float4 meshPosition = meshUniform.transform * vertices[vid].position;
    outVert.shadowPosition0 = lightCast.lightCastMatrix[0] * meshPosition;
    outVert.shadowPosition1 = lightCast.lightCastMatrix[1] * meshPosition;
    return outVert;
}


fragment float4 fragment_light_shadow(ProjectedVertex vert [[stage_in]],
                                      constant LightUniform &lightUniform [[buffer(0)]],
                                      constant ModelCharacterUniforms &modelCharacterUniforms [[buffer(1)]],
                                      texture2d<float> shadowMap0 [[texture(0)]],
                                      texture2d<float> shadowMap1 [[texture(1)]],
                                      sampler samplr [[sampler(0)]])
{
    float3 normal = normalize(vert.normal);
    float3 ambientTerm = kShadowOverlay ? 0.0 : lightUniform.ambientDensity * material.ambientColor;
    float3 colorForLights = 0.0;
    
    float shadowOverlay = 0.0;
    float surfaceBrightness = 0.0;
    
    texture2d<float> shadowMap[2] = {shadowMap0, shadowMap1};
    const float4 shadowPosition[2] = {vert.shadowPosition0, vert.shadowPosition1};
    
    for (unsigned i = 0; i < 4; ++i)
    {
        float diffuseIntensity = saturate(dot(normal, normalize(lightUniform.direction[i].xyz)));
        
        if (kShadowOverlay)
        {
            float shadowPercent = 0.0;
            if (i < 2)
            {
                shadowPercent = shadow_coverage_common(shadowPosition[i],
                                                       lightUniform.shadowBias[i], diffuseIntensity,
                                                       lightUniform.shadowSoften[i], 3,
                                                       shadowMap[i], samplr);
            }
            
            shadowOverlay += lightUniform.density[i] * diffuseIntensity * shadowPercent;
            surfaceBrightness += lightUniform.density[i] * diffuseIntensity;
        }
        else
        {
            float3 diffuseTerm = material.diffuseColor * diffuseIntensity;
            
            float3 specularTerm(0);
            if (diffuseIntensity > 0)
            {
                float3 eyeDirection = normalize(vert.eye);
                float3 halfway = normalize(normalize(lightUniform.direction[i].xyz) + eyeDirection);
                float specularFactor = pow(saturate(dot(normal, halfway)), material.specularPower);
                specularTerm = material.specularColor * specularFactor;
            }
            
            float shadowPercent = 0.0;
            if (i < 2)
            {
                shadowPercent = shadow_coverage_common(shadowPosition[i],
                                                       lightUniform.shadowBias[i], diffuseIntensity,
                                                       lightUniform.shadowSoften[i], 3,
                                                       shadowMap[i], samplr);
            }
            
            colorForLights += (diffuseTerm * lightUniform.density[i] + specularTerm * lightUniform.spacular[i]) * (1.0 - shadowPercent);
        }
    }
    
    if (kShadowOverlay)
        return float4(0.0, 0.0, 0.0, shadowOverlay / surfaceBrightness);
    else
        return float4(ambientTerm + colorForLights, modelCharacterUniforms.opacity);
}


float4 fragment_light_tex_materialed_common(VertexFragmentCharacters vert,
                                            float3 normal,
                                            constant LightUniform &lightingUniform,
                                            float4 diffuseTexel,
                                            texture2d<float> shadowMap[2],
                                            sampler samplr)
{
    normal = normalize(normal);
    
    float3 diffuseColor = diffuseTexel.rgb * vert.diffuseColor;
    float opacity = diffuseTexel.a * vert.opacity;
    
    float3 ambientTerm = lightingUniform.ambientDensity * vert.ambientColor;
    float3 colorForLights = 0.0;
    
    float transparency = (1 - opacity);
    
    for (unsigned i = 0; i < 4; ++i)
    {
        float3 lightVector = normalize(lightingUniform.direction[i].xyz);
        float diffuseIntensity = saturate(dot(normal, lightVector));
        float3 diffuseTerm = diffuseColor * diffuseIntensity;
        
        float3 specularTerm(0);
        if (diffuseIntensity > 0)
        {
            float3 eyeDirection = normalize(vert.eye);
            float3 halfway = normalize(lightVector + eyeDirection);
            
            specularTerm = specular_common(vert.specularColor, vert.specularPower,
                                           lightingUniform.direction[i].xyz,
                                           lightingUniform.density[i],
                                           lightingUniform.spacular[i],
                                           normal, halfway, diffuseIntensity);
            transparency *= ((1 - saturate(pow(length(specularTerm), 1.0))));
        }
        
        float shadowPercent = 0.0;
        if (i < 2)
        {
            shadowPercent = shadow_coverage_common(vert.shadowPosition[i],
                                                   lightingUniform.shadowBias[i], diffuseIntensity,
                                                   lightingUniform.shadowSoften[i], 3,
                                                   shadowMap[i], samplr);
        }
        
        colorForLights += (diffuseTerm * lightingUniform.density[i] + specularTerm) *
                          (1 - shadowPercent);
    }
    
    return float4(ambientTerm + colorForLights, 1.0 - transparency);
}



ProjectedVertex vertex_project_common(device Vertex *vertices,
                                      constant NuoUniforms &uniforms,
                                      constant NuoMeshUniforms &meshUniform,
                                      uint vid [[vertex_id]])
{
    ProjectedVertex outVert;
    float4 meshPosition = meshUniform.transform * vertices[vid].position;
    float3 meshNormal = meshUniform.normalTransform * vertices[vid].normal.xyz;
    
    outVert.position = uniforms.viewProjectionMatrix * meshPosition;
    outVert.eye =  -(uniforms.viewMatrix * meshPosition).xyz;
    outVert.normal = meshNormal;
    
    return outVert;
}



float4 diffuse_common(float4 diffuseTexel, float extraOpacity)
{
    if (kAlphaChannelInSeparatedTexture)
    {
        diffuseTexel = diffuseTexel / diffuseTexel.a;
        diffuseTexel.a = extraOpacity;
    }
    else if (kAlphaChannelInTexture)
    {
        diffuseTexel = float4(diffuseTexel.rgb / diffuseTexel.a, diffuseTexel.a);
    }
    else
    {
        if (diffuseTexel.a < 1e-9)
            diffuseTexel.rgb = float3(1.0);
        else
            diffuseTexel = diffuseTexel / diffuseTexel.a;
        
        diffuseTexel.a = 1.0;
    }
    
    return diffuseTexel;
}



// see p233 real-time rendering
// see https://seblagarde.wordpress.com/2011/08/17/hello-world/
//
float3 fresnel_schlick(float3 specularColor, float3 lightVector, float3 halfway)
{
    return specularColor + (1.0f - specularColor) * pow(1.0f - saturate(dot(lightVector, halfway)), 5);
}


float3 specular_common(float3 materialSpecularColor, float materialSpecularPower,
                       float3 lightVector,
                       float lightIntensity,
                       float lightSpecularIntensity,
                       float3 normal, float3 halfway, float dotNL)
{
    float dotNHPower = pow(saturate(dot(normal, halfway)), materialSpecularPower);
    float specularFactor = dotNHPower * dotNL;
    float3 adjustedCsepcular = materialSpecularColor * lightSpecularIntensity;
    
    if (kPhysicallyReflection)
    {
        return fresnel_schlick(adjustedCsepcular / 3.0, lightVector, halfway) *
               ((materialSpecularPower + 2) / 8) * specularFactor * lightIntensity;
    }
    else
    {
        return adjustedCsepcular * specularFactor;
    }
}




float shadow_coverage_common(metal::float4 shadowCastModelPostion,
                             float shadowBiasFactor, float shadowedSurfaceAngle,
                             float shadowSoftenFactor, float shadowMapSampleRadius,
                             metal::texture2d<float> shadowMap, metal::sampler samplr)
{
    float shadowMapBias = 0.002;
    shadowMapBias += shadowBiasFactor * (1 - shadowedSurfaceAngle);
    
    const float kSampleSizeBase = 1.0 / 1800.0;
    float sampleSize = kSampleSizeBase * (1 + shadowSoftenFactor);
    
    float2 shadowCoord = shadowCastModelPostion.xy / shadowCastModelPostion.w;
    shadowCoord.x = (shadowCoord.x + 1) * 0.5;
    shadowCoord.y = (-shadowCoord.y + 1) * 0.5;
    
    float modelDepth = (shadowCastModelPostion.z / shadowCastModelPostion.w) - shadowMapBias;
    
    // find PCSS blocker and calculate the penumbra factor according to it
    //
    float penumbraFactor = 1.0;
    if (kShadowPCSS)
    {
        float blocker = 0;
        int blockerSampleCount = 0;
        
        const float searchSampleSize = sampleSize * 40.0;
        const float searchRegion = shadowMapSampleRadius * searchSampleSize;
        const float searchDiameter = shadowMapSampleRadius * 2;
        
        float xCurrentSearch = shadowCoord.x - searchRegion;
        
        for (int i = 0; i < searchDiameter; ++i)
        {
            float yCurrentSearch = shadowCoord.y - searchRegion;
            for (int j = 0; j < searchDiameter; ++j)
            {
                float shadowDepth = shadowMap.sample(samplr, float2(xCurrentSearch, yCurrentSearch)).x;
                if (shadowDepth < modelDepth)
                {
                    blockerSampleCount += 1;
                    blocker += shadowDepth;
                }
                
                yCurrentSearch += searchSampleSize;
            }
            
            xCurrentSearch += searchSampleSize;
        }
        
        blocker /= blockerSampleCount;
        penumbraFactor = (modelDepth - blocker) / blocker;
    }
    
    int shadowCoverage = 0;
    int shadowSampleCount = 0;
    
    // PCSS-based penumbra
    //
    if (kShadowPCSS)
        sampleSize = kSampleSizeBase * 0.5 + sampleSize * (penumbraFactor * 25.0);
    
    const float shadowRegion = shadowMapSampleRadius * sampleSize;
    const float shadowDiameter = shadowMapSampleRadius * 2;
    
    float xCurrent = shadowCoord.x - shadowRegion;
    
    for (int i = 0; i < shadowDiameter; ++i)
    {
        float yCurrent = shadowCoord.y - shadowRegion;
        for (int j = 0; j < shadowDiameter; ++j)
        {
            shadowSampleCount += 1;
            
            float2 current = float2(xCurrent, yCurrent) +
                                // randomized offset to avoid quantization
                                (rand(shadowCastModelPostion.x + shadowCastModelPostion.y + i + j) - 0.5) *
                                sampleSize * 0.5;
            
            float shadowDepth = shadowMap.sample(samplr, current).x;
            
            // increase the shadow bias in proportion to the distance to the sampling point
            //
            if (kShadowPCSS)
            {
                if (shadowDepth < modelDepth -
                    shadowMapBias * length(current - shadowCoord) / sampleSize *
                    (penumbraFactor * 4.0) /* PCSS effect compensation */)
                {
                    shadowCoverage += 1;
                }
            }
            else
            {
                if (shadowDepth < modelDepth -
                    shadowMapBias * length(current - shadowCoord) / sampleSize)
                {
                    shadowCoverage += 1;
                }
            }
            
            yCurrent += sampleSize;
        }
        
        xCurrent += sampleSize;
    }
    
    if (shadowCoverage > 0)
    {
        float l = saturate(smoothstep(0, 0.2, shadowedSurfaceAngle));
        float t = smoothstep((rand(shadowCastModelPostion.x + shadowCastModelPostion.y)) * 0.5, 1.0f, l);
        
        float shadowPercent = shadowCoverage / (float)shadowSampleCount * t;
        return shadowPercent;
    }
    
    /** simpler shadow without PCF
     *
    float shadowDepth = shadowMap.sample(samplr, shadowCoord).x;
    if (shadowDepth < modelDepth)
        return 1.0; */
    
    return 0.0;
}


float rand(float2 co)
{
    return fract(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
}



