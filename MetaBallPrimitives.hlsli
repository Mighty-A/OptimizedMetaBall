#ifndef METABALLPRIMITIVES_H
#define METABALLPRIMITIVES_H

#include "RaytracingShaderHelper.hlsli"

//#define INTERVAL_REFINEMENT
#define MAX_METABALLS_PER_CAL 10
// MetaBall resources
					StructuredBuffer<Metaball> g_metaballs : register(t4, space0);
					
// Calculate field potential from all active metaballs.
float CalculateMetaballsPotential(in float3 position, in Metaball blobs[MAX_METABALLS_PER_CAL], in UINT nActiveMetaballs)
{
    float sumFieldPotential = 0;
    for (UINT j = 0; j < nActiveMetaballs; j++)
    {
        float dummy;
        sumFieldPotential += CalculateMetaballPotential(position, blobs[j], dummy);
    }
    return sumFieldPotential;
}


bool RayMetaballIntersectionTest(in Ray localRay, in MetaBall metaBall, inout float thit)
{
	float tmin = INFINITY;
	float tmax = -INFINITY;
	
	float _thit, _tmax;
	
	
	if (RaySolidSphereIntersectionTest(localRay, _thit, _tmax, metaBall.center, metaBall.radius))
	{
	   thit = _thit;
	   return true;
	}
	return false;
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
float3 CalculateMetaballNormal(in float3 position, in Metaball blobs[MAX_METABALLS_PER_CAL], in UINT nActiveMetaballs)
{
	/*
    float e = 0.5773 * 0.00001;
    return normalize(float3(
        CalculateMetaballsPotential(position + float3(-e, 0, 0), blobs, nActiveMetaballs) -
        CalculateMetaballsPotential(position + float3(e, 0, 0), blobs, nActiveMetaballs),
        CalculateMetaballsPotential(position + float3(0, -e, 0), blobs, nActiveMetaballs) -
        CalculateMetaballsPotential(position + float3(0, e, 0), blobs, nActiveMetaballs),
        CalculateMetaballsPotential(position + float3(0, 0, -e), blobs, nActiveMetaballs) -
        CalculateMetaballsPotential(position + float3(0, 0, e), blobs, nActiveMetaballs)));
	*/
	float3 norm = { 0, 0, 0 };
    for (UINT j = 0; j < nActiveMetaballs; ++j)
    {
        norm += CalculateMetaballNormal(position, blobs[j]);
    }
    return normalize(norm);
}
bool RayMetaBallPostIntersectionTest(in Ray localRay, in RayPayload payload, out float thit, out float3 normal)
{
	const float3 Translation = float3(0.0f, 1.0f, 0.0f);

	UINT numOfMetaBalls = 0;
	float tmin = INFINITY;
	float tmax = -INFINITY;
	uint j = 0;
	float smin = INFINITY;
	float start = RayTMin();

	MetaBall metaBalls[MAX_METABALLS_PER_CAL];
	const float innerRatio = 0.74f;
	for (int i = 0; i < MAX_INDEX_BUFFER_LENGTH; i++) {
		if (j >= MAX_METABALLS_PER_CAL || !(payload.bit[i / 32] & (1U << (i % 32)))){
			continue;
		}
		MetaBall m = g_metaballs[i];
		m.center += Translation;
		//metaBalls[i].center = mul(WorldToObject3x4(), float4(metaBalls[i].center, 1.0f));
		//metaBalls[i].radius = length(mul(WorldToObject3x4(), float4(metaBalls[i].radius, 0.0f, 0.0f, 0.0f)));
		float _thit, _tmax;
		if (RaySolidSphereIntersectionTest(localRay, _thit, _tmax, m.center, m.radius))
        {
#ifdef INTERVAL_REFINEMENT
			if (_thit > smin || _thit < start) {
				continue;
			}
			float _shit, _smax;
            // test inner
            if (RaySolidSphereIntersectionTest(localRay, _shit, _smax, m.center, m.radius * innerRatio)) {
                smin = min(_shit, smin);
            }
#endif
            tmin = min(_thit, tmin);
            tmax = max(_tmax, tmax);
			metaBalls[j++] = m;
		}
	}
	
	numOfMetaBalls = j;
	
	tmin = max(tmin, RayTMin());
	tmax = min(tmax, RayTCurrent());
	UINT MAX_STEPS = 256;
	
    float t = tmin;
    float minTStep = (tmax - tmin) / (MAX_STEPS);
    UINT iStep = 0;
	const float Threshold = 0.1f;
	
	
	float3 position = localRay.origin + t * localRay.direction;
	float sumFieldpotential = 0;
	for (i = 0; i < numOfMetaBalls; i++)
	{
	   	float distance;
		float tempPotential = CalculateMetaballPotential(position, metaBalls[i], distance);
		sumFieldpotential += tempPotential;
	}
	bool fromInside = sumFieldpotential > Threshold;
	
	while (iStep++ < MAX_STEPS) 
	{
		float3 position = localRay.origin + t * localRay.direction;
		float sumFieldpotential = 0;
		for (UINT j = 0; j < numOfMetaBalls; j++)
		{
	   		float distance;
			float tempPotential = CalculateMetaballPotential(position, metaBalls[j], distance);
			sumFieldpotential += tempPotential;
		}
		
		if (!fromInside && sumFieldpotential >= Threshold)
		{
			normal = CalculateMetaballNormal(position, metaBalls, numOfMetaBalls);
			if (IsAValidHit(localRay, t, normal))
			{
				thit = t;
				return true;
			}
		}
		if (fromInside && sumFieldpotential <= Threshold)
		{
			normal = CalculateMetaballNormal(position, metaBalls, numOfMetaBalls);
			if (IsAValidHit(localRay, t, normal))
			{
				thit = t;
				return true;
			}
		}
		t += minTStep;
		
	}
	return false;
}

/*
bool ShadowRayMetaBallPostIntersectionTest(in Ray localRay, in ShadowRayPayload payload, out float thit)
{
	UINT numOfMetaBalls = payload.indexCount;
	float tmin = INFINITY;
	float tmax = -INFINITY;
	MetaBall metaBalls[MAX_INDEX_BUFFER_LENGTH];
	for (UINT i = 0; i < numOfMetaBalls; i++) {
		metaBalls[i] = g_metaballs[payload.indexBuffer[i]];
		float _thit, _tmax;
		if (RaySolidSphereIntersectionTest(localRay, _thit, _tmax, metaBalls[i].center, metaBalls[i].radius))
        {
            tmin = min(_thit, tmin);
            tmax = max(_tmax, tmax);
		}
	}
	tmin = max(tmin, RayTMin());
	tmax = min(tmax, RayTCurrent());
	UINT MAX_STEPS = 128;
	
    float t = tmin;
    float minTStep = (tmax - tmin) / (MAX_STEPS / 1);
    UINT iStep = 0;
	const float Threshold = 0.25f;
	
	while (iStep++ < MAX_STEPS) 
	{
		float3 position = localRay.origin + t * localRay.direction;
		float sumFieldpotential;
		for (UINT j = 0; j < numOfMetaBalls; j++)
		{
	   		float distance;
			float tempPotential = CalculateMetaballPotential(position, metaBalls[j], distance);
			sumFieldpotential += tempPotential;
		}
		
		if (sumFieldpotential >= Threshold)
		{
			return true;
		}
		t += minTStep;
		
	}
	
	return false;
}*/
#endif /*METABALLPRIMITIVES_H*/