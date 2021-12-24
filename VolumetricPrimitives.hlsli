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

//**********************************************************************************************
//
// VolumetricPrimitives.hlsli
//
// Ray marching of Metaballs (aka "Blobs").
// More info here: https://www.scratchapixel.com/lessons/advanced-rendering/rendering-distance-fields/blobbies
//
//**********************************************************************************************

#ifndef VOLUMETRICPRIMITIVESLIBRARY_H
#define VOLUMETRICPRIMITIVESLIBRARY_H


#include "RaytracingShaderHelper.hlsli"

struct Metaball
{
    float3 center;
    float  radius;
};

// Calculate a magnitude of an influence from a Metaball charge.
// Return metaball potential range: <0,1>
// mbRadius - largest possible area of metaball contribution - AKA its bounding sphere.
float CalculateMetaballPotential(in float3 position, in Metaball blob, out float distance)
{
    distance = length(position - blob.center);
    
    if (distance <= blob.radius)
    {
        float d = distance;

        // Quintic polynomial field function.
        // The advantage of this polynomial is having smooth second derivative. Not having a smooth
        // second derivative may result in a sharp and visually unpleasant normal vector jump.
        // The field function should return 1 at distance 0 from a center, and 1 at radius distance,
        // but this one gives f(0) = 0, f(radius) = 1, so we use the distance to radius instead.
        d = blob.radius - d;

        float r = d / blob.radius;
        return r * r * r * (r * (r * 6 - 15) + 10);
    }
    return 0;
}

// Calculate field potential from all active metaballs.
float CalculateMetaballsPotential(in float3 position, in Metaball blobs[N_METABALLS], in UINT nActiveMetaballs)
{
    float sumFieldPotential = 0;
#if USE_DYNAMIC_LOOPS 
    for (UINT j = 0; j < nActiveMetaballs; j++)
#else
    for (UINT j = 0; j < N_METABALLS; j++)
#endif
    {
        float dummy;
        sumFieldPotential += CalculateMetaballPotential(position, blobs[j], dummy);
    }
    return sumFieldPotential;
}

float3 CalculateMetaballNormal(in float3 position, in Metaball blob)
{
    float3 direction = position - blob.center;
    float distance = length(direction);

    if (distance < blob.radius)
    {
        float d = blob.radius - distance;
        float r = d / blob.radius;
        float len = 30 / (d * distance) * r * r * r * (r - 1) * (r - 1);
        return direction * len;
    }
    return float3(0, 0, 0);
}

// Calculate a normal via central differences.
float3 CalculateMetaballsNormal(in float3 position, in Metaball blobs[N_METABALLS], in UINT nActiveMetaballs)
{
    //float e = 0.5773 * 0.00001;
    //return normalize(float3(
    //    CalculateMetaballsPotential(position + float3(-e, 0, 0), blobs, nActiveMetaballs) -
    //    CalculateMetaballsPotential(position + float3(e, 0, 0), blobs, nActiveMetaballs),
    //    CalculateMetaballsPotential(position + float3(0, -e, 0), blobs, nActiveMetaballs) -
    //    CalculateMetaballsPotential(position + float3(0, e, 0), blobs, nActiveMetaballs),
    //    CalculateMetaballsPotential(position + float3(0, 0, -e), blobs, nActiveMetaballs) -
    //    CalculateMetaballsPotential(position + float3(0, 0, e), blobs, nActiveMetaballs)
    //));

    float3 norm = { 0, 0, 0 };
    for (UINT j = 0; j < nActiveMetaballs; ++j)
    {
        norm += CalculateMetaballNormal(position, blobs[j]);
    }
    return normalize(norm);
}

void InitializeAnimatedMetaballs(out Metaball blobs[N_METABALLS], in float elapsedTime, in float cycleDuration)
{
    // Metaball centers at t0 and t1 key frames.
#if N_METABALLS == 10
    float3 keyFrameCenters[N_METABALLS][2] =
    {
        { float3(-0.7, 0, 0),float3(0.7,0, 0) },
        { float3(0.7 , 0, 0), float3(-0.7, 0, 0) },
        { float3(0, -0.7, 0),float3(0, 0.7, 0) },
        { float3(0, 0.7, 0), float3(0, -0.7, 0) },
        { float3(0, 0, 0),   float3(0, 0, 0) },
        { float3(-0.7, -0.7, 0),float3(0.7,0.7, 0) },
        { float3(0.7 , 0.7, 0), float3(-0.7, -0.7, 0) },
        { float3(0.7, -0.7, 0),float3(-0.7, 0.7, 0) },
        { float3(-0.7, 0.7, 0), float3(0.7, -0.7, 0) },
         
    };
    // Metaball field radii of max influence
    float radii[N_METABALLS] = { 0.35, 0.35, 0.35, 0.35, 0.25, 0.35, 0.35, 0.35, 0.35};
#elif N_METABALLS == 27
    // layers means the distance of the inner ball to the surface
    const int layers = 1;
    float3 keyFrameCenters[N_METABALLS][2];
    // Metaball field radii of max influence
    float radii[N_METABALLS];
    uint index = 0;
    float offset = 0.7;
    // [-layers, layers]
    
    [unroll] for (int x = -layers; x <= layers; x++) {
        [unroll] for (int y = -layers; y <= layers; y++) {
            [unroll] for (int z=  -layers; z <= layers; z++) {
                keyFrameCenters[index][0] = float3(x * offset, y * offset, z * offset);
                keyFrameCenters[index][1] = -keyFrameCenters[index][0];
                radii[index] = 0.25;
                index += 1;
            }
        } 
    }
 #elif N_METABALLS == 125
    // layers means the distance of the inner ball to the surface
    const int layers = 2;
    float3 keyFrameCenters[N_METABALLS][2];
    // Metaball field radii of max influence
    float radii[N_METABALLS];
    uint index = 0;
    float offset = 0.3;
    // [-layers, layers]
    
    [unroll]for (int x = -layers; x <= layers; x++) {
        [unroll]for (int y = -layers; y <= layers; y++) {
            [unroll]for (int z=  -layers; z <= layers; z++) {
                keyFrameCenters[index][0] = float3(x * offset, y * offset, z * offset);
                keyFrameCenters[index][1] = -keyFrameCenters[index][0];
                radii[index] = 0.15;
                index += 1;
            }
        } 
    }


#else //N_METABALLS == 3
    float3 keyFrameCenters[N_METABALLS][2] =
    {
        { float3(-0.5, 0, 0), float3( 0.5, 0, 0) },
        { float3( 0.5, 0, 0), float3(-0.5, 0, 0) },   
        //{ float3(0, 0, 0), float3(0, 0, 0)},
    };
    // Metaball field radii of max influence
    float radii[N_METABALLS] = { 0.35, 0.35,/* 0.2*/ };
#endif

    // Calculate animated metaball center positions.
    float  tAnimate = CalculateAnimationInterpolant(elapsedTime, cycleDuration);
    for (UINT j = 0; j < N_METABALLS; j++)
    {
        blobs[j].center = lerp(keyFrameCenters[j][0], keyFrameCenters[j][1], tAnimate);
        blobs[j].radius = radii[j];
    }
}

// Find all metaballs that ray intersects.
// The passed in array is sorted to the first nActiveMetaballs.
void FindIntersectingMetaballs(in Ray ray, out float tmin, out float tmax, inout Metaball blobs[N_METABALLS], out UINT nActiveMetaballs)
{
    // Find the entry and exit points for all metaball bounding spheres combined.
    tmin = INFINITY;
    tmax = -INFINITY;

    nActiveMetaballs = 0;
    for (UINT i = 0; i < N_METABALLS; i++)
    {
        float _thit, _tmax;
        if (RaySolidSphereIntersectionTest(ray, _thit, _tmax, blobs[i].center, blobs[i].radius))
        {
            tmin = min(_thit, tmin);
            tmax = max(_tmax, tmax);
#if LIMIT_TO_ACTIVE_METABALLS
            blobs[nActiveMetaballs++] = blobs[i];
#else
            nActiveMetaballs = N_METABALLS;
#endif
        }
    }
    tmin = max(tmin, RayTMin());
    tmax = min(tmax, RayTCurrent());
}

// Test if a ray with RayFlags and segment <RayTMin(), RayTCurrent()> intersects metaball field.
// The test sphere traces through the metaball field until it hits a threshold isosurface. 
bool RayMetaballsIntersectionTest(in Ray ray, out float thit, out ProceduralPrimitiveAttributes attr, in float elapsedTime)
{
    Metaball blobs[N_METABALLS];
    InitializeAnimatedMetaballs(blobs, elapsedTime, 24.0f);
    
    float tmin, tmax;   // Ray extents to first and last metaball intersections.
    UINT nActiveMetaballs = 0;  // Number of metaballs's that the ray intersects.
    FindIntersectingMetaballs(ray, tmin, tmax, blobs, nActiveMetaballs);

    UINT MAX_STEPS = 128;
    float t = tmin;
    float minTStep = (tmax - tmin) / (MAX_STEPS / 1);
    UINT iStep = 0;
	const float Threshold = 0.25f;


    float3 position = ray.origin + t * ray.direction;
    float fieldPotentials[N_METABALLS];    // Field potentials for each metaball.
    float sumFieldPotential = 0;  
#if USE_DYNAMIC_LOOPS
        for (UINT j = 0; j < nActiveMetaballs; j++)
#else
        for (UINT j = 0; j < N_METABALLS; j++)
#endif
        {
            float distance;
            fieldPotentials[j] = CalculateMetaballPotential(position, blobs[j], distance);
            sumFieldPotential += fieldPotentials[j];
         }
    bool fromInside = sumFieldPotential > Threshold;
    

    while (iStep++ < MAX_STEPS)
    {
        float3 position = ray.origin + t * ray.direction;
        float fieldPotentials[N_METABALLS];    // Field potentials for each metaball.
        float sumFieldPotential = 0;           // Sum of all metaball field potentials.
            
        // Calculate field potentials from all metaballs.
#if USE_DYNAMIC_LOOPS
        for (UINT j = 0; j < nActiveMetaballs; j++)
#else
        for (UINT j = 0; j < N_METABALLS; j++)
#endif
        {
            float distance;
            fieldPotentials[j] = CalculateMetaballPotential(position, blobs[j], distance);
            sumFieldPotential += fieldPotentials[j];
         }

        // Field potential threshold defining the isosurface.
        // Threshold - valid range is (0, 1>, the larger the threshold the smaller the blob.

        // Have we crossed the isosurface?
        if (!fromInside && sumFieldPotential > Threshold)
        {
            float3 normal = CalculateMetaballsNormal(position, blobs, nActiveMetaballs);
            if (IsAValidHit(ray, t, normal))
            //if (IsInRange(t, RayTMin(), RayTCurrent()))
            {
                thit = t;
                attr.normal = normal;
                return true;
            }
        }
        if (fromInside && sumFieldPotential <= Threshold)
        {
            float3 normal = CalculateMetaballsNormal(position, blobs, nActiveMetaballs);
            if (IsAValidHit(ray, t, normal))
            //if (IsInRange(t, RayTMin(), RayTCurrent()))
            {
                thit = t;
                attr.normal = normal;
                return true;
            }
            //thit = t;
            //attr.normal = normal;
            //return true;    
        }
        t += minTStep;
    }

    return false;
}

#endif // VOLUMETRICPRIMITIVESLIBRARY_H