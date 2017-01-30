﻿/*
Copyright 2017 by kosmonautgames

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

// Uniform color for skinned meshes
// Draws a mesh with one color only

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Variables
#include "helper.fx"

#define SKINNED_EFFECT_MAX_BONES   72

float3 CameraPosition;

float4x4 ViewProj;
float4x4 World;
float3x3 WorldIT;

float4x3 Bones[SKINNED_EFFECT_MAX_BONES];

float Metallic = 0.3f;
bool UseMetallicMap = false;
float Roughness = 0.3f;
bool UseRoughnessMap = false;

float4 AlbedoColor = float4(1, 1, 1, 1);
bool UseAlbedoMap = false;

bool UseLinear = true;


Texture2D<float4> NormalMap;
Texture2D<float4> AlbedoMap;
Texture2D<float4> MetallicMap;
Texture2D<float4> RoughnessMap;

Texture2D<float4> FresnelMap;
TextureCube<float4> EnvironmentMap;

sampler TextureSampler
{
	Texture = (Texture);
	Filter = Anisotropic;
	MaxAnisotropy = 8;
	AddressU = Wrap;
	AddressV = Wrap;
};

SamplerState FresnelSampler = sampler_state
{
	Texture = <FresnelMap>;
	MinFilter = LINEAR;
	MagFilter = LINEAR; 
	Mipfilter = LINEAR;

	AddressU = Clamp;
	AddressV = Clamp;
};

SamplerState CubeMapSampler
{
	texture = <EnvironmentMap>;
	AddressU = CLAMP;
	AddressV = CLAMP;
	MagFilter = LINEAR;
	MinFilter = LINEAR;
	Mipfilter = LINEAR;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Structs

struct VertexShaderInput
{
	float4 Position : POSITION0;
	float3 Normal   : NORMAL0;
	float2 TexCoord : TEXCOORD0;
};

struct Normal_VertexShaderInput
{
	float4 Position : POSITION0;
	float3 Normal : NORMAL0;
	float3 Binormal : BINORMAL0;
	float3 Tangent : TANGENT0;
	float2 TexCoord : TEXCOORD0;
};

struct SkinnedVertexShaderInput
{
	float4 Position : POSITION0;
	float3 Normal   : NORMAL0;
	float2 TexCoord : TEXCOORD0;
	uint4  Indices  : BLENDINDICES0;
	float4 Weights  : BLENDWEIGHT0;
};

struct SkinnedNormal_VertexShaderInput
{
	float4 Position : POSITION0;
	float3 Normal : NORMAL0;
	float3 Binormal : BINORMAL0;
	float3 Tangent : TANGENT0;
	float2 TexCoord : TEXCOORD0;
	uint4  Indices  : BLENDINDICES0;
	float4 Weights  : BLENDWEIGHT0;
};

struct VertexShaderOutput
{
	float4 Position : SV_POSITION;
    float3 Normal : NORMAL;
	float2 TexCoord : TEXCOORD0;
	float3 WorldPosition : TEXCOORD2;
}; 

struct Normal_VertexShaderOutput
{
	float4 Position : SV_POSITION0;
	float3x3 WorldToTangentSpace : TEXCOORD3;
	float2 TexCoord : TEXCOORD1;
	float3 WorldPosition : TEXCOORD2;
	//float Depth : TEXCOORD0;
};

struct LightingParams
{
	float4 Color : COLOR0;
	float3 Normal : TEXCOORD0;
	float Metallic : TEXCOORD1;
	float Roughness : TEXCOORD2;
	float3 WorldPosition : TEXCOORD3;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Functions

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  VS

void SkinNormal(inout SkinnedVertexShaderInput vin, uniform int boneCount)
{
	float4x3 skinning = 0;

	[unroll]
	for (int i = 0; i < boneCount; i++)
	{
		skinning += Bones[vin.Indices[i]] * vin.Weights[i];
	}

	vin.Position.xyz = mul(vin.Position, skinning);
	vin.Normal = mul(vin.Normal, (float3x3)skinning);
}

void SkinTangentSpace(inout SkinnedNormal_VertexShaderInput vin, uniform int boneCount)
{
	float4x3 skinning = 0;

	[unroll]
	for (int i = 0; i < boneCount; i++)
	{
		skinning += Bones[vin.Indices[i]] * vin.Weights[i];
	}

	vin.Position.xyz = mul(vin.Position, skinning);
	vin.Normal = mul(vin.Normal, (float3x3)skinning);
	vin.Binormal = mul(vin.Binormal, (float3x3)skinning);
	vin.Tangent = mul(vin.Tangent, (float3x3)skinning);
}

VertexShaderOutput Unskinned_VertexShaderFunction(VertexShaderInput input)
{
	VertexShaderOutput output;

	float4 WorldPosition = mul(input.Position, World);
	output.WorldPosition = WorldPosition.xyz;
	output.Position = mul(WorldPosition, ViewProj);
	output.Normal = mul(input.Normal, WorldIT).xyz;
	output.TexCoord = input.TexCoord;
	return output;
}

Normal_VertexShaderOutput UnskinnedNormalMapped_VertexShaderFunction(Normal_VertexShaderInput input)
{
	Normal_VertexShaderOutput output;

	float4 WorldPosition = mul(input.Position, World);
	output.WorldPosition = WorldPosition.xyz;

	output.Position = mul(WorldPosition, ViewProj);
	output.WorldToTangentSpace[0] = mul(input.Tangent, WorldIT);
	output.WorldToTangentSpace[1] = mul(input.Binormal, WorldIT);
	output.WorldToTangentSpace[2] = mul(input.Normal, WorldIT);
	output.TexCoord = input.TexCoord;

	//output.WorldPosition = WorldPos.xyz;
	return output;
}

//4 weights per vertex
VertexShaderOutput Skinned_VertexShaderFunction(SkinnedVertexShaderInput input)
{
	VertexShaderOutput output;

	SkinNormal(input, 4);

	float4 WorldPosition = mul(input.Position, World);
	output.WorldPosition = WorldPosition.xyz;
    output.Position = mul(WorldPosition, ViewProj);
	output.Normal = mul(input.Normal, WorldIT).xyz;
	output.TexCoord = input.TexCoord;
	return output;
}

Normal_VertexShaderOutput SkinnedNormalMapped_VertexShaderFunction(SkinnedNormal_VertexShaderInput input)
{
	Normal_VertexShaderOutput output;

	SkinTangentSpace(input, 4);

	float4 WorldPosition = mul(input.Position, World);
	output.WorldPosition = WorldPosition.xyz;

	output.Position = mul(WorldPosition,ViewProj);
	output.WorldToTangentSpace[0] = mul(input.Tangent, WorldIT);
	output.WorldToTangentSpace[1] = mul(input.Binormal, WorldIT);
	output.WorldToTangentSpace[2] = mul(input.Normal, WorldIT);
	output.TexCoord = input.TexCoord;
	
	//output.WorldPosition = WorldPos.xyz;
	return output;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  PS

float3 GetNormalMap(float2 TexCoord)
{
	//This gets normalized anyways, so it doesn't matter that it's technically only half the length
	return NormalMap.Sample(TextureSampler, TexCoord).rgb - float3(0.5f, 0.5f, 0.5f);
}

float4 Lighting(LightingParams input)
{
	float3 normal = normalize(input.Normal);

	float4 color = input.Color;
	if (UseLinear) color = pow(abs(color), 2.2f);

	float metallic = input.Metallic;
	float roughness = input.Roughness;

	const float3 lightVector = normalize(float3(0, 0, 1/*-0.8f, -0.8f, 0.3f*/));
	const float lightIntensity = 1;
	const float3 lightColor = float3(0, 0, 0);
	float3 viewDir = normalize(input.WorldPosition - CameraPosition);

	float f0 = lerp(0.04f, color.g * 0.25 + 0.75, metallic);

	float NdL = /*saturate((dot(normal, lightVector) + 0.5f) / 1.5f);*/saturate(dot(normal, lightVector));
	float3 diffuseLight = 0;
	[branch]
	if (metallic < 0.99)
	{
		//diffuseLight = DiffuseOrenNayar(NdL, normal, lightVector, -cameraDirection, lightIntensity, lightColor, roughness); //NdL * lightColor.rgb;
		diffuseLight = NdL*0;
	}
	float3 specularLight = float3(0,0,0);// SpecularCookTorrance(NdL, normal, lightVector, -viewDir, lightIntensity, lightColor, f0, roughness);

	diffuseLight = (diffuseLight * (1 - f0)); //* (1 - f0)) * (f0 + 1) * (f0 + 1);

	float2 fresnelFactor = FresnelMap.Sample(FresnelSampler, float2(roughness, 1-dot(-viewDir, normal))).rg;

	float3 reflectVector = -reflect(-viewDir, normal);

	float4 specularReflection = EnvironmentMap.SampleLevel(CubeMapSampler, reflectVector.xzy, (roughness) * 8);
	if (UseLinear) specularReflection = pow(abs(specularReflection), 2.2f);

	specularReflection = specularReflection * (fresnelFactor.r * f0 + fresnelFactor.g);
	//specularReflection = lerp(float4(0, 0, 0, 0), specularReflection, fresnelFactor);

	float4 diffuseReflection = EnvironmentMap.SampleLevel(CubeMapSampler, reflectVector.xzy,6) ;
	if (UseLinear) diffuseReflection = pow(abs(diffuseReflection), 2.2f);

	diffuseReflection *= (1 - (fresnelFactor.r * f0 + fresnelFactor.g));
	//float envMapCoord = saturate((-normal.z + 1) / 2);

	//float4 ambientDiffuse = float4(EnvironmentMap.Load(int3(127, envMapCoord * 128, 0), int2(0, 0)).rgb, 1); //EnvironmentMap.Sample(EnvironmentMapSampler, float2(1.0f, envMapCoord)); EnvironmentMap.Load(int3(1, envMapCoord * 128, 0), int2(0, 0)); // EnvironmentMap.SampleLevel(EnvironmentMapSampler, float2(-1, envMapCoord), 0)*10;
	//float4 ambientSpecular = EnvironmentMap.Load(int3(input.Roughness * 128, envMapCoord * 128, 0), int2(0, 0)); //EnvironmentMap.Load(int3(0, envMapCoord * 128, 0), int2(0, 0));

	//ambientDiffuse = pow(abs(ambientDiffuse), 2.2f) * EnvironmentIntensity;
	//ambientSpecular = pow(abs(ambientSpecular), 4.4f) * EnvironmentIntensity;

	//float strength = lerp(ambientSpecular.a * 2, 1, metallic);

	//ambientSpecular = float4(ambientSpecular.rgb *strength, 1);

	float3 plasticFinal = color.rgb * (diffuseLight + diffuseReflection)+specularLight + specularReflection; //ambientSpecular;
	if (UseLinear) plasticFinal = pow(abs(plasticFinal), 0.45454545f);

	float3 metalFinal = (specularLight + specularReflection)* color.rgb;
	if (UseLinear) metalFinal = pow(abs(metalFinal), 0.45454545f);

	float3 finalValue = lerp(plasticFinal, metalFinal, metallic);
/*
	if (UseLinear) finalValue = pow(abs(finalValue), 0.45454545f);
*/
	return float4(finalValue, 1);
}

float4 PixelShaderFunction(VertexShaderOutput input) : SV_TARGET0
{
	float3 normal = input.Normal;
	///*input.WorldToTangentSpace[2];*/GetNormalMap(input.TexCoord);
	////normal = normalize(mul(normal, input.WorldToTangentSpace));
	float sampleLevel = AlbedoMap.CalculateLevelOfDetail(TextureSampler, input.TexCoord);

	float4 albedo = AlbedoColor;//AlbedoMap.Sample(TextureSampler, input.TexCoord);

	[branch]
	if (UseAlbedoMap)
	{
		albedo = AlbedoMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel);
	}

	float roughness = Roughness;
	[branch]
	if (UseRoughnessMap)
	{
		roughness = RoughnessMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel);
	}

	float metallic = Metallic;
	[branch]
	if (UseMetallicMap)
	{
		metallic = MetallicMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel);
	}

	LightingParams renderParams;

	renderParams.Color = albedo;
	renderParams.Normal = normal;
	////renderParams.Depth = input.Depth;
	renderParams.Metallic = metallic;
	renderParams.Roughness = roughness;
	renderParams.WorldPosition = input.WorldPosition;

	return Lighting(renderParams);
}

float4 TangentSpace_PixelShaderFunction(Normal_VertexShaderOutput input) : SV_TARGET0
{
	float sampleLevel = AlbedoMap.CalculateLevelOfDetail(TextureSampler, input.TexCoord);

	float4 albedo = AlbedoColor;//AlbedoMap.Sample(TextureSampler, input.TexCoord);

	[branch]
	if (UseAlbedoMap)
	{
		albedo = AlbedoMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel);
	}

	float roughness = Roughness;
	[branch]
	if (UseRoughnessMap)
	{
		roughness = RoughnessMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel);
	}

	float metallic = Metallic;
	[branch]
	if (UseMetallicMap)
	{
		metallic = MetallicMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel);
	}

	float3 normalMap = NormalMap.SampleLevel(TextureSampler, input.TexCoord, sampleLevel).xyz - float3(0.5f, 0.5f, 0.5f);

	float3 normal = normalize(mul(normalMap, input.WorldToTangentSpace));

	LightingParams renderParams;

	renderParams.Color = albedo;
	renderParams.Normal = normal;
	////renderParams.Depth = input.Depth;
	renderParams.Metallic = metallic;
	renderParams.Roughness = roughness;
	renderParams.WorldPosition = input.WorldPosition;

	return Lighting(renderParams);
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Techniques

technique Unskinned
{
	pass Pass1
	{
		VertexShader = compile vs_5_0 Unskinned_VertexShaderFunction();
		PixelShader = compile ps_5_0 PixelShaderFunction();
	}
}

technique UnskinnedNormalMapped
{
	pass Pass1
	{
		VertexShader = compile vs_5_0 UnskinnedNormalMapped_VertexShaderFunction();
		PixelShader = compile ps_5_0 TangentSpace_PixelShaderFunction();
	}
}

technique Skinned
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 Skinned_VertexShaderFunction();
        PixelShader = compile ps_5_0 PixelShaderFunction();
    }
}

technique SkinnedNormalMapped
{
	pass Pass1
	{
		VertexShader = compile vs_5_0 SkinnedNormalMapped_VertexShaderFunction();
		PixelShader = compile ps_5_0 TangentSpace_PixelShaderFunction();
	}
}
