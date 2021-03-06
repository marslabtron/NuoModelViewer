//
//  ShadersCommon.h
//  ModelViewer
//
//  Created by dfeng on 11/11/16.
//  Copyright © 2016 middleware. All rights reserved.
//

#ifndef ShadersCommon_h
#define ShadersCommon_h

#include <metal_stdlib>
#include <metal_matrix>

#include "NuoUniforms.h"
#include "NuoMeshUniform.h"


struct Material
{
    metal::float3 ambientColor;
    metal::float3 diffuseColor;
    metal::float3 specularColor;
    float specularPower;
};

constant Material material = {
    .ambientColor = { 0.6, 0.6, 0.6 },
    .diffuseColor = { 0.6, 0.6, 0.6 },
    .specularColor = { 1, 1, 1 },
    .specularPower = 100
};

struct Light
{
    metal::float3 diffuseColor;
    metal::float3 specularColor;
};

constant Light light = {
    .diffuseColor = { 1, 1, 1 },
    .specularColor = { 0.5, 0.5, 0.5 }
};


struct VertexFragmentCharacters
{
    metal::float3 eye;
    
    metal::float3 diffuseColor;
    metal::float3 ambientColor;
    metal::float3 specularColor;
    float specularPower;
    float opacity;
    
    metal::float4 shadowPosition[2];
};


struct PositionSimple
{
    metal::float4 position [[position]];
};


constant bool kAlphaChannelInTexture            [[ function_constant(0) ]];
constant bool kAlphaChannelInSeparatedTexture   [[ function_constant(1) ]];
constant bool kPhysicallyReflection             [[ function_constant(2) ]];
constant bool kShadowOverlay                    [[ function_constant(3) ]];
constant bool kShadowPCSS                       [[ function_constant(4) ]];



metal::float4 fragment_light_tex_materialed_common(VertexFragmentCharacters vert,
                                                   metal::float3 normal,
                                                   constant LightUniform &lighting,
                                                   metal::float4 diffuseTexel,
                                                   metal::texture2d<float> shadowMap[2],
                                                   metal::sampler samplr);


fragment void fragment_shadow(PositionSimple vert [[stage_in]]);


metal::float4 diffuse_common(metal::float4 diffuseTexel, float extraOpacity);


metal::float3 specular_common(metal::float3 materialSpecularColor, float materialSecularPower,
                              metal::float3 lightVector,
                              float lightIntensity,
                              float lightSpecularIntensity,
                              metal::float3 normal, metal::float3 halfway, float dotNL);


float shadow_coverage_common(metal::float4 shadowCastModelPostion,
                             float shadowBiasFactor, float shadowedSurfaceAngle,
                             float shadowSoftenFactor, float shadowMapSampleRadius,
                             metal::texture2d<float> shadowMap, metal::sampler samplr);

float rand(metal::float2 co);



#endif /* ShadersCommon_h */
