//*********************************************************
//
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
//*********************************************************

#ifndef RAYTRACING_HLSL
#define RAYTRACING_HLSL

#define HLSL
#include "RaytracingHlslCompat.h"
#include "ProceduralPrimitivesLibrary.hlsli"
#include "RaytracingShaderHelper.hlsli"


//***************************************************************************
//*****------ Shader resources bound via root signatures -------*************
//***************************************************************************

// Scene wide resources.
//  g_* - bound via a global root signature.
//  l_* - bound via a local root signature.
RaytracingAccelerationStructure g_scene : register(t0, space0);
RWTexture2D<float4> g_renderTarget : register(u0);
ConstantBuffer<SceneConstantBuffer> g_sceneCB : register(b0);

// Triangle resources
ByteAddressBuffer g_indices : register(t1, space0);
StructuredBuffer<Vertex> g_vertices : register(t2, space0);

// Procedural geometry resources
StructuredBuffer<PrimitiveInstancePerFrameBuffer> g_AABBPrimitiveAttributes : register(t3, space0);
ConstantBuffer<PrimitiveConstantBuffer> l_materialCB : register(b1);
ConstantBuffer<PrimitiveInstanceConstantBuffer> l_aabbCB: register(b2);

ConstantBuffer<MetaBall> l_metaBall : register(b2);



//***************************************************************************
//****************------ Utility functions -------***************************
//***************************************************************************

// Diffuse lighting calculation.
float CalculateDiffuseCoefficient(in float3 hitPosition, in float3 incidentLightRay, in float3 normal)
{
    float fNDotL = saturate(dot(-incidentLightRay, normal));
    return fNDotL;
}

// Phong lighting specular component
float4 CalculateSpecularCoefficient(in float3 hitPosition, in float3 incidentLightRay, in float3 normal, in float specularPower)
{
    float3 reflectedLightRay = normalize(reflect(incidentLightRay, normal));
    return pow(saturate(dot(reflectedLightRay, normalize (-WorldRayDirection()))), specularPower);
}


// Phong lighting model = ambient + diffuse + specular components.
float4 CalculatePhongLighting(in float4 albedo, in float3 normal, in bool isInShadow, in float diffuseCoef = 1.0, in float specularCoef = 1.0, in float specularPower = 50)
{
    float3 hitPosition = HitWorldPosition();
    float3 lightPosition = g_sceneCB.lightPosition.xyz;
    float shadowFactor = isInShadow ? InShadowRadiance : 1.0;
    float3 incidentLightRay = normalize(hitPosition - lightPosition);

    // Diffuse component.
    float4 lightDiffuseColor = g_sceneCB.lightDiffuseColor;
    float Kd = CalculateDiffuseCoefficient(hitPosition, incidentLightRay, normal);
    float4 diffuseColor = shadowFactor * diffuseCoef * Kd * lightDiffuseColor * albedo;

    // Specular component.
    float4 specularColor = float4(0, 0, 0, 0);
    if (!isInShadow)
    {
        float4 lightSpecularColor = float4(1, 1, 1, 1);
        float4 Ks = CalculateSpecularCoefficient(hitPosition, incidentLightRay, normal, specularPower);
        specularColor = specularCoef * Ks * lightSpecularColor;
    }

    // Ambient component.
    // Fake AO: Darken faces with normal facing downwards/away from the sky a little bit.
    float4 ambientColor = g_sceneCB.lightAmbientColor;
    float4 ambientColorMin = g_sceneCB.lightAmbientColor - 0.1;
    float4 ambientColorMax = g_sceneCB.lightAmbientColor;
    float a = 1 - saturate(dot(normal, float3(0, -1, 0)));
    ambientColor = albedo * lerp(ambientColorMin, ambientColorMax, a);
    
    return ambientColor + diffuseColor + specularColor;
}

// Phong lighting model = ambient + diffuse + specular components.
float4 CalculatePhongLightingSpecial(in float3 hitPosition, in float4 albedo, in float3 normal, in bool isInShadow, in float diffuseCoef = 1.0, in float specularCoef = 1.0, in float specularPower = 50)
{
    float3 lightPosition = g_sceneCB.lightPosition.xyz;
    float shadowFactor = isInShadow ? InShadowRadiance : 1.0;
    float3 incidentLightRay = normalize(hitPosition - lightPosition);

    // Diffuse component.
    float4 lightDiffuseColor = g_sceneCB.lightDiffuseColor;
    float Kd = CalculateDiffuseCoefficient(hitPosition, incidentLightRay, normal);
    float4 diffuseColor = shadowFactor * diffuseCoef * Kd * lightDiffuseColor * albedo;

    // Specular component.
    float4 specularColor = float4(0, 0, 0, 0);
    if (!isInShadow)
    {
        float4 lightSpecularColor = float4(1, 1, 1, 1);
        float4 Ks = CalculateSpecularCoefficient(hitPosition, incidentLightRay, normal, specularPower);
        specularColor = specularCoef * Ks * lightSpecularColor;
    }

    // Ambient component.
    // Fake AO: Darken faces with normal facing downwards/away from the sky a little bit.
    float4 ambientColor = g_sceneCB.lightAmbientColor;
    float4 ambientColorMin = g_sceneCB.lightAmbientColor - 0.1;
    float4 ambientColorMax = g_sceneCB.lightAmbientColor;
    float a = 1 - saturate(dot(normal, float3(0, -1, 0)));
    ambientColor = albedo * lerp(ambientColorMin, ambientColorMax, a);
    
    return ambientColor + diffuseColor + specularColor;
}

//***************************************************************************
//*****------ TraceRay wrappers for radiance and shadow rays. -------********
//***************************************************************************

// Trace a radiance ray into the scene and returns a shaded color.
float4 TraceRadianceRay(in Ray ray, in UINT currentRayRecursionDepth, in RAY_FLAG flag = RAY_FLAG_CULL_BACK_FACING_TRIANGLES)
{
    if (currentRayRecursionDepth >= MAX_RAY_RECURSION_DEPTH)
    {
        return float4(0, 0, 0, 0);
    }

    // Set the ray's extents.
    RayDesc rayDesc;
    rayDesc.Origin = ray.origin;
    rayDesc.Direction = ray.direction;
    // Set TMin to a zero value to avoid aliasing artifacts along contact areas.
    // Note: make sure to enable face culling so as to avoid surface face fighting.
    rayDesc.TMin = 0.000;
    rayDesc.TMax = 10000;
    RayPayload rayPayload = { float4(0, 0, 0, 0), currentRayRecursionDepth + 1,
    
#if MAX_INDEX_BUFFER_LENGTH > 0
    0,
#endif
#if MAX_INDEX_BUFFER_LENGTH > 32
    0,
#endif 
#if MAX_INDEX_BUFFER_LENGTH > 64
    0,
#endif 
#if MAX_INDEX_BUFFER_LENGTH > 96
    0, 
#endif
#if MAX_INDEX_BUFFER_LENGTH > 128
    0,
#endif
#if MAX_INDEX_BUFFER_LENGTH >= 1000
   
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 
#endif
    /* 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0*/
					};
    TraceRay(g_scene,
        flag,
        TraceRayParameters::InstanceMask,
        TraceRayParameters::HitGroup::Offset[RayType::Radiance],
        0, //TraceRayParameters::HitGroup::GeometryStride,
        TraceRayParameters::MissShader::Offset[RayType::Radiance],
        rayDesc, rayPayload);
    

    
  

    return rayPayload.color;
}

// Trace a shadow ray and return true if it hits any geometry.
bool TraceShadowRayAndReportIfHit(in Ray ray, in UINT currentRayRecursionDepth)
{
    return false;
    if (currentRayRecursionDepth >= MAX_RAY_RECURSION_DEPTH)
    {
        return false;
    }

    // Set the ray's extents.
    RayDesc rayDesc;
    rayDesc.Origin = ray.origin;
    rayDesc.Direction = ray.direction;
    // Set TMin to a zero value to avoid aliasing artifcats along contact areas.
    // Note: make sure to enable back-face culling so as to avoid surface face fighting.
    rayDesc.TMin = 0.000;
    rayDesc.TMax = 10000;

    // Initialize shadow ray payload.
    // Set the initial value to true since closest and any hit shaders are skipped. 
    // Shadow miss shader, if called, will set it to false.
    ShadowRayPayload shadowPayload = { true};
    
    TraceRay(g_scene,
        RAY_FLAG_CULL_BACK_FACING_TRIANGLES
        | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH
        | RAY_FLAG_FORCE_OPAQUE             // ~skip any hit shaders
        | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER, // ~skip closest hit shaders,
        TraceRayParameters::InstanceMask,
        TraceRayParameters::HitGroup::Offset[RayType::Shadow],
        TraceRayParameters::HitGroup::GeometryStride,
        TraceRayParameters::MissShader::Offset[RayType::Shadow],
        rayDesc, shadowPayload);
        
    return shadowPayload.hit;
}

//***************************************************************************
//********************------ Ray gen shader.. -------************************
//***************************************************************************

[shader("raygeneration")]
void MyRaygenShader()
{
    // Generate a ray for a camera pixel corresponding to an index from the dispatched 2D grid.
    Ray ray = GenerateCameraRay(DispatchRaysIndex().xy, g_sceneCB.cameraPosition.xyz, g_sceneCB.projectionToWorld);
 
    // Cast a ray into the scene and retrieve a shaded color.
    UINT currentRecursionDepth = 0;
    float4 color = TraceRadianceRay(ray, currentRecursionDepth);

    // Write the raytraced color to the output texture.
    g_renderTarget[DispatchRaysIndex().xy] = color;
}

//***************************************************************************
//******************------ Closest hit shaders -------***********************
//***************************************************************************


inline bool AnyMetaBallsIntersection(inout RayPayload rayPayload) 
{
    UINT sum = 0;
    for (UINT i = 0; i < MAX_INDEX_BUFFER_LENGTH / 32 + 1; i += 1U) {
        sum += rayPayload.bit[i];
    }
    if (sum != 0) {
        Ray localray;
        localray.direction = WorldRayDirection();
        localray.origin = WorldRayOrigin();
        float thit = 0, _thit, _tmax;
        float3 normal = 0;
        if (RayMetaBallPostIntersectionTest(localray, rayPayload, thit, normal)) {
            
            // Constant
            float4 albedo = float4(0.549f, 0.555f, 0.554f, 1.0f);
            float reflectedCoef = 1.0f;
            float refractionCoef = 1.0f;
            float diffuseCoef = 0.9f;
            float specularCoef = 0.7f;
            float specularPower = 50.0f;
            
            // shadow (unabled)
            float3 hitPosition = localray.origin + localray.direction * thit;
            Ray shadowRay = { hitPosition, normalize(g_sceneCB.lightPosition.xyz - hitPosition) };
            bool shadowRayHit = TraceShadowRayAndReportIfHit(shadowRay, rayPayload.recursionDepth);
#ifdef PREFER_PERFORMANCE
            // From inside test
            albedo = float4(0.020f, 0.020f, 0.020f, 1.0f);
            bool fromInside = dot(localray.direction, normal) > 0;
            float4 refractionColor = float4(0, 0, 0, 0); 
            float4 reflectedColor = float4(0, 0, 0, 0);
            if (fromInside) 
            {
                float eta = 1.33;
                float biasStep = 0.00001;       
                normal = -normal;
                float3 refractDirect = refract(localray.direction, normal, eta);
                
                if (length(refractDirect) == 0)
                {              
                    if (reflectedCoef > 0.001)
                    {
                        // Trace a reflection ray.
                        float3 reflectDirect = reflect(localray.direction, normal);
                        Ray reflectionRay = { hitPosition + biasStep * reflectDirect,  reflectDirect};
                        float4 reflectionColor = TraceRadianceRay(reflectionRay, rayPayload.recursionDepth, RAY_FLAG_CULL_BACK_FACING_TRIANGLES);

                        reflectedColor = float4(1.0f, 0.0f, 0.0f, 1.0f);//reflectedCoef  * reflectionColor;
                    }
                } else
                {
                    // Trace a reflection ray.
                    float3 fresnelR = TotalFresnelReflectanceSchlick(localray.direction, normal, albedo.xyz);
 
                    if (reflectedCoef > 0.001)
                    {
                        // Trace a reflection ray.
                        float3 reflectDirect = reflect(localray.direction, normal);
                        Ray reflectionRay = { hitPosition + biasStep * reflectDirect,  reflectDirect};
                        float4 reflectionColor = TraceRadianceRay(reflectionRay, rayPayload.recursionDepth, RAY_FLAG_CULL_FRONT_FACING_TRIANGLES);

                        reflectedColor = reflectedCoef * float4(fresnelR, 1) * reflectionColor;
                    }
                            
                    // refraction
       
                    if (refractionCoef > 0.001) 
                    {
                        Ray refractionRay = { hitPosition + biasStep * refractDirect, refractDirect};

                        refractionColor = TraceRadianceRay(refractionRay, rayPayload.recursionDepth, RAY_FLAG_CULL_BACK_FACING_TRIANGLES); // add extra trace for entering medium
        
                        refractionColor = float4(0.0f, 1.0f, 0.0f, 1.0f);//refractionCoef * float4(1 - fresnelR, 1) * refractionColor;
                    }  
                }
            } else {
                float eta = 1.0 / 1.33;
                float biasStep = 0.0001; 
                float3 refractDirect = refract(localray.direction, normal, eta);
                        
                // Trace a reflection ray.
                float3 fresnelR = FresnelReflectanceSchlick(localray.direction, normal, albedo.xyz);
 
                if (reflectedCoef > 0.001)
                {
                    // Trace a reflection ray.
                    float3 reflectDirect = reflect(localray.direction, normal);
                    Ray reflectionRay = { hitPosition + biasStep * reflectDirect,  reflectDirect};
                    float4 reflectionColor = TraceRadianceRay(reflectionRay, rayPayload.recursionDepth, RAY_FLAG_CULL_BACK_FACING_TRIANGLES);

                    reflectedColor = reflectedCoef * float4(fresnelR, 1) * reflectionColor;
                }
                            
                // refraction
       
                if (refractionCoef > 0.001) 
                {
                    Ray refractionRay = { hitPosition + biasStep * refractDirect, refractDirect};

                    refractionColor = TraceRadianceRay(refractionRay, rayPayload.recursionDepth, RAY_FLAG_CULL_BACK_FACING_TRIANGLES); // add extra trace for entering medium
        
                    refractionColor = refractionCoef * float4(1 - fresnelR, 1) * refractionColor;
                }       
            }
            float4 phongColor = CalculatePhongLightingSpecial(hitPosition, albedo, normal, shadowRayHit, diffuseCoef, specularCoef, specularPower);
            float4 color = 0 * phongColor + reflectedColor + refractionColor;
            rayPayload.color = color;
#else
	        float3 fresnelR = FresnelReflectanceSchlick(localray.direction, normal, albedo.xyz);
            // Reflected component.
            float4 reflectedColor = float4(0, 0, 0, 0);
            if (reflectedCoef > 0.001)
            {
                // Trace a reflection ray.
                Ray reflectionRay = { hitPosition, reflect(localray.direction, normal) };
                float4 reflectionColor = TraceRadianceRay(reflectionRay, rayPayload.recursionDepth);


                reflectedColor = 1.0f * float4(fresnelR, 1) * reflectionColor;
            }
            // Calculate final color.
            float4 phongColor = CalculatePhongLightingSpecial(hitPosition, albedo, normal, shadowRayHit, diffuseCoef, specularCoef, specularPower);
            float4 color = phongColor + reflectedColor;
            
            rayPayload.color = color;
#endif
            return true;
        }
    }
    return false;
}

[shader("closesthit")]
void MyClosestHitShader_Triangle(inout RayPayload rayPayload, in BuiltInTriangleIntersectionAttributes attr)
{
    if (AnyMetaBallsIntersection(rayPayload)) {
        return;
    }
    
    // Get the base index of the triangle's first 16 bit index.
    uint indexSizeInBytes = 2;
    uint indicesPerTriangle = 3;
    uint triangleIndexStride = indicesPerTriangle * indexSizeInBytes;
    uint baseIndex = PrimitiveIndex() * triangleIndexStride;

    // Load up three 16 bit indices for the triangle.
    const uint3 indices = Load3x16BitIndices(baseIndex, g_indices);

    // Retrieve corresponding vertex normals for the triangle vertices.
    float3 triangleNormal = g_vertices[indices[0]].normal;

    // PERFORMANCE TIP: it is recommended to avoid values carry over across TraceRay() calls. 
    // Therefore, in cases like retrieving HitWorldPosition(), it is recomputed every time.

    // Shadow component.
    // Trace a shadow ray.
    float3 hitPosition = HitWorldPosition();
    Ray shadowRay = { hitPosition, normalize(g_sceneCB.lightPosition.xyz - hitPosition) };
    bool shadowRayHit = TraceShadowRayAndReportIfHit(shadowRay, rayPayload.recursionDepth);

    float checkers = AnalyticalCheckersTexture(HitWorldPosition(), triangleNormal, g_sceneCB.cameraPosition.xyz, g_sceneCB.projectionToWorld);

    // Reflected component.
    float4 reflectedColor = float4(0, 0, 0, 0);
    if (l_materialCB.reflectanceCoef > 0.001 )
    {
        // Trace a reflection ray.
        Ray reflectionRay = { HitWorldPosition(), reflect(WorldRayDirection(), triangleNormal) };
        float4 reflectionColor = TraceRadianceRay(reflectionRay, rayPayload.recursionDepth);

        float3 fresnelR = FresnelReflectanceSchlick(WorldRayDirection(), triangleNormal, l_materialCB.albedo.xyz);
        reflectedColor = l_materialCB.reflectanceCoef * float4(fresnelR, 1) * reflectionColor;
    }

    // Calculate final color.
    float4 phongColor = CalculatePhongLighting(l_materialCB.albedo, triangleNormal, shadowRayHit, l_materialCB.diffuseCoef, l_materialCB.specularCoef, l_materialCB.specularPower);
    float4 color = checkers * (phongColor + reflectedColor);

    // Apply visibility falloff.
    float t = RayTCurrent();
    color = lerp(color, BackgroundColor, 1.0 - exp(-0.000002*t*t*t));
    rayPayload.color = color;
}

[shader("closesthit")]
void MyClosestHitShader_AABB(inout RayPayload rayPayload, in ProceduralPrimitiveAttributes attr)
{
    // PERFORMANCE TIP: it is recommended to minimize values carry over across TraceRay() calls. 
    // Therefore, in cases like retrieving HitWorldPosition(), it is recomputed every time.

    // Shadow component.
    // Trace a shadow ray.
    float3 hitPosition = HitWorldPosition();
    Ray shadowRay = { hitPosition, normalize(g_sceneCB.lightPosition.xyz - hitPosition) };
    bool shadowRayHit = TraceShadowRayAndReportIfHit(shadowRay, rayPayload.recursionDepth);

	float3 fresnelR = FresnelReflectanceSchlick(WorldRayDirection(), attr.normal, l_materialCB.albedo.xyz);
    // Reflected component.
    float4 reflectedColor = float4(0, 0, 0, 0);
    if (l_materialCB.reflectanceCoef > 0.001)
    {
        // Trace a reflection ray.
        Ray reflectionRay = { HitWorldPosition(), reflect(WorldRayDirection(), attr.normal) };
        float4 reflectionColor = TraceRadianceRay(reflectionRay, rayPayload.recursionDepth);


        reflectedColor = l_materialCB.reflectanceCoef * float4(fresnelR, 1) * reflectionColor;
    }
    
    // refraction
    float4 refractionColor = float4(0, 0, 0, 0);    
    if (l_materialCB.refractionCoef > 0.001) {
        // Trace a refraction ray.
        float refractivity = 1.33;
        bool inside = dot(WorldRayDirection(), attr.normal) > 0;
        
        float eta = inside ? refractivity : 1.0f / refractivity;
        float3 tempNormal = attr.normal * (inside ? -1.0f: 1.0f);
        float3 newDire = refract(WorldRayDirection(), tempNormal, eta);
        if (length(newDire) > 0) {
            Ray refractionRay = { HitWorldPosition(), newDire};

            refractionColor = TraceRadianceRay(refractionRay, rayPayload.recursionDepth); // add extra trace for entering medium
        
            refractionColor = l_materialCB.refractionCoef * /*float4(float3(1, 1, 1) - fresnelR, 1) */  refractionColor;
        }
    }
    // Calculate final color.
    
    float4 phongColor = CalculatePhongLighting(l_materialCB.albedo, attr.normal, shadowRayHit, l_materialCB.diffuseCoef, l_materialCB.specularCoef, l_materialCB.specularPower);
    float4 color = phongColor + reflectedColor + refractionColor;

    // Apply visibility falloff.
    float t = RayTCurrent();
    color = lerp(color, BackgroundColor, 1.0 - exp(-0.000002*t*t*t));

    rayPayload.color = color;
}

[shader("closesthit")]
void MyClosestHitShader_MetaBallPrimitive(inout RayPayload rayPayload, in ProceduralPrimitiveAttributes attr)
{    
    if (AnyMetaBallsIntersection(rayPayload)) 
    {
        return;
    }
}

//***************************************************************************
//**********************------ Miss shaders -------**************************
//***************************************************************************

[shader("miss")]
void MyMissShader(inout RayPayload rayPayload)
{
    float4 backgroundColor = float4(BackgroundColor);
    if (AnyMetaBallsIntersection(rayPayload)) {
        return;
    }
    
        rayPayload.color = backgroundColor;
}

[shader("miss")]
void MyMissShader_ShadowRay(inout ShadowRayPayload rayPayload)
{
    rayPayload.hit = false;
}

//***************************************************************************
//*****************------ Intersection shaders-------************************
//***************************************************************************

// Get ray in AABB's local space.
Ray GetRayInAABBPrimitiveLocalSpace()
{
    PrimitiveInstancePerFrameBuffer attr = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];

    // Retrieve a ray origin position and direction in bottom level AS space 
    // and transform them into the AABB primitive's local space.
    Ray ray;
    ray.origin = mul(float4(ObjectRayOrigin(), 1), attr.bottomLevelASToLocalSpace).xyz;
    ray.direction = mul(ObjectRayDirection(), (float3x3) attr.bottomLevelASToLocalSpace);
    return ray;
}

[shader("intersection")]
void MyIntersectionShader_AnalyticPrimitive()
{
    Ray localRay = GetRayInAABBPrimitiveLocalSpace();
    AnalyticPrimitive::Enum primitiveType = (AnalyticPrimitive::Enum) l_aabbCB.primitiveType;
    
    float thit;
    ProceduralPrimitiveAttributes attr = (ProceduralPrimitiveAttributes)0;
    if (RayAnalyticGeometryIntersectionTest(localRay, primitiveType, thit, attr))
    {
        PrimitiveInstancePerFrameBuffer aabbAttribute = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];
        attr.normal = mul(attr.normal, (float3x3) aabbAttribute.localSpaceToBottomLevelAS);
        attr.normal = normalize(mul((float3x3) ObjectToWorld3x4(), attr.normal));

        ReportHit(thit, /*hitKind*/ 0, attr);
    }
}

[shader("intersection")]
void MyIntersectionShader_VolumetricPrimitive()
{
    Ray localRay = GetRayInAABBPrimitiveLocalSpace();
    VolumetricPrimitive::Enum primitiveType = (VolumetricPrimitive::Enum) l_aabbCB.primitiveType;
    
    float thit;
    ProceduralPrimitiveAttributes attr = (ProceduralPrimitiveAttributes)0;
    if (RayVolumetricGeometryIntersectionTest(localRay, primitiveType, thit, attr, g_sceneCB.elapsedTime))
    {
        PrimitiveInstancePerFrameBuffer aabbAttribute = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];
        attr.normal = mul(attr.normal, (float3x3) aabbAttribute.localSpaceToBottomLevelAS);
        attr.normal = normalize(mul((float3x3) ObjectToWorld3x4(), attr.normal));

        ReportHit(thit, /*hitKind*/ 0, attr);
    }
}

[shader("intersection")]
void MyIntersectionShader_SignedDistancePrimitive()
{
	Ray localRay = GetRayInAABBPrimitiveLocalSpace();
    SignedDistancePrimitive::Enum primitiveType = (SignedDistancePrimitive::Enum) l_aabbCB.primitiveType;

    float thit;
    ProceduralPrimitiveAttributes attr = (ProceduralPrimitiveAttributes)0;
    if (RaySignedDistancePrimitiveTest(localRay, primitiveType, thit, attr, l_materialCB.stepScale))
    {
        PrimitiveInstancePerFrameBuffer aabbAttribute = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];
        attr.normal = mul(attr.normal, (float3x3) aabbAttribute.localSpaceToBottomLevelAS);
        attr.normal = normalize(mul((float3x3) ObjectToWorld3x4(), attr.normal));
        
        ReportHit(thit, /*hitKind*/ 0, attr);
    }
}


[shader("intersection")]
void MyIntersectionShader_MetaBallPrimitive()
{
    
    Ray localRay;
    localRay.direction = ObjectRayDirection();
    localRay.origin = ObjectRayOrigin();
    
    
    int primitiveIndex = GeometryIndex();
    
    MetaBallPrimitiveAttributes attr = (MetaBallPrimitiveAttributes)0;
    
	MetaBall metaBall = g_metaballs[primitiveIndex];
    
    /*
    metaBall.center = mul( WorldToObject3x4(), float4(metaBall.center, 1.0f));
    float4 r = float4(metaBall.radius, 0.0f, 0.0f, 0.0f);
    metaBall.radius = length(mul(WorldToObject3x4(), r));*/
    attr.index = primitiveIndex;
    MetaBall innerBall = metaBall;
    innerBall.radius *= 0.74f;
    bool hitOuter = false;
	float S_hit;
    if (RayMetaballIntersectionTest(localRay, metaBall, S_hit))
    {
        hitOuter = true;
        float s_hit;
        if (S_hit > RayTMin() && S_hit < RayTCurrent())
            ReportHit(S_hit, 0, attr);
        /*
        if (RayMetaballIntersectionTest(localRay, innerBall, s_hit))
        {
            attr.hitType = 0;
            if (s_hit > RayTMin())
                ReportHit(s_hit, 0, attr);
        } else
        {
            attr.hitType = 1;
            if (S_hit < RayTCurrent())
                ReportHit(S_hit, 0, attr);
        }*/
    }
    

}


//***************************************************************************
//*****************------ Any Hit shaders-------************************
//***************************************************************************


[shader("anyhit")]
void MyAnyhitShader_MetaBallPrimitive(inout RayPayload payload, in MetaBallPrimitiveAttributes attr)
{
    
    payload.bit[(int)attr.index / 32] |= (1U << ((int)attr.index % 32));
        IgnoreHit();
    // give control back to the Intersection Shader
}

#endif // RAYTRACING_HLSL
