// invis fx 0.1

extern float invisint = 1;
extern float warpint = 1;
static const float wspeed = -0.3;
static const float thres = 0.3;
static const float thresm = 1.3;

#define PI 3.1415926535897932384626433832795
#define N 8  

#define TAU 6.28318530718

#define TILING_FACTOR 1.0
#define MAX_ITER 6

static const float hscale = 0.19;
matrix mview;
matrix mproj;
float2 rcpres;
bool isInterior;

float time;

texture lastshader;
texture lastpass;
texture depthframe;

texture tex1 < string src="warpfxnorm.dds"; >;

sampler s0 = sampler_state { texture = <lastshader>; addressu = mirror; addressv = mirror; magfilter = linear; minfilter = linear; };
sampler s1 = sampler_state { texture = <lastpass>; addressu = mirror; addressv = mirror; magfilter = linear; minfilter = linear; };

sampler sdepth = sampler_state { texture = <depthframe>; addressu = wrap; addressv = wrap; magfilter = linear; minfilter = linear; };

sampler warpSampler = sampler_state { texture = <tex1>; addressu = wrap; addressv = wrap; magfilter = linear; minfilter = linear; };

float4 sample0(sampler2D s, float2 t)
{
    return tex2Dlod(s, float4(t, 0, 0));
}

float3 toWorld(float2 tex)
{
    float3 v = float3(mview[0][2], mview[1][2], mview[2][2]);
    v += (1/mproj[0][0] * (2*tex.x-1)).xxx * float3(mview[0][0], mview[1][0], mview[2][0]);
    v += (-1/mproj[1][1] * (2*tex.y-1)).xxx * float3(mview[0][1], mview[1][1], mview[2][1]);
    return v;
}

float2 cylindrical(float2 tex)
{
    float3 worldpos = toWorld(tex);
    float u = -atan2(worldpos.y, worldpos.x) / PI;
    float v = -worldpos.z / length(worldpos.xy);
    return float2(0.5 * u + 0.5, hscale * v);
}

float waterHighlight(float2 p, float time)
{
    float2 i = float2(p);
	float c = 0.0;
    float foaminess_factor = 1.81;
	float inten = .005 * foaminess_factor;

	for (int n = 0; n < MAX_ITER; n++) 
	{
		float t = time * (1.0 - (3.5 / float(n+1)));
		i = p + float2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
		c += 1.0/length(float2(p.x / (sin(i.x+t)),p.y / (cos(i.y+t))));
	}
	c = 0.2 + c / (inten * float(MAX_ITER));
	c = 1.17-pow(c, 1.4);
    c = pow(abs(c), 8.0);
	return c / sqrt(foaminess_factor);
}



float4 brightpass( float2 Tex : TEXCOORD0 ) : COLOR0
{
	float4 col = sample0(s0, Tex) * 1.4;
	
	col = max( col - thres, 0.0 );
	col /= 1.0 + col;
	col *= thresm;
	col = lerp(col, dot(col, float3(0.299,0.587,0.114)), 0.7);
	//col.rgb = lerp(col.rgb, float3(0.8,0.6,0.7), saturate(col.rgb * 10));
	return col;
}



float4 warpfx(in float2 tex : TEXCOORD) : COLOR0
{
	float dmask = tex2D(sdepth, tex).r;
	float inoff = lerp(1.0, 0.5, isInterior);
	float fmask = smoothstep(500 * inoff, 3000  * inoff, dmask);
	
	
	float maskint = 1.0 - smoothstep(0,5500, dmask);
	dmask = smoothstep(55, 60, dmask);
	
	float timetick = time * wspeed;
	float2 uv = cylindrical(tex);
	
	float ftime = timetick * 0.4 + 23.0;
	
	float2 p = fmod(uv*TAU, TAU)-250.0;
	
	
	
	
	

	//float middle = abs(saturate(abs(uv.g)) - 1);
	float middle = 1.0 - min(1.0, abs(uv.g));
	middle = pow(middle, 4.0);

	float2 warpn = sample0(warpSampler, float2(uv * float2(2.0,-2.0) + float2(0.0, timetick))) + 0.5;

	warpn = lerp(1.0, lerp(float2(1.0, 1.0), warpn * dmask, warpint), dmask * middle);
	
	warpn = lerp(warpn, float2(1.0, 1.0), lerp(1, float2(0.95, 0.7), maskint));
	float2 warpnless = lerp(warpn, float2(1.0, 1.0), lerp(1, float2(0.99, 0.8), maskint));
	
	float4 orgorg = sample0(s0, tex);
	float4 org = sample0(s0, tex * warpnless);
		
	float4 px = tex2D(s1, tex * warpn);
	
	float c = waterHighlight(p, ftime);
	
	float3 water_color = float3(0.0, 0.35, 0.5);
	float3 colorfog = saturate(c + water_color);
	
	
	colorfog = lerp(water_color, colorfog, middle);
	
	
	
	float3 comb = org.rgb + px.rgb;
	comb = lerp(comb, inoff * colorfog,saturate( fmask + colorfog * 0.0005 + dot(1.0, warpn) * 0.0005));
	
	
	comb = lerp(comb, dot(float3(0.299,0.587,0.114), comb), 0.6);
	
	float3 contrasted = comb*comb*comb*(comb*(comb*6.0 - 15.0) + 10.0);
	comb.rgb = lerp(comb.rgb, contrasted, 0.5);

	comb = lerp(comb, comb * float3(0.83,0.95,0.87), 3);
	
	
	
	comb = lerp(orgorg, comb * 1.2, invisint);
	return float4(comb, 1.0);
}


technique T0 < string MGEinterface="MGE XE 0"; >
{
    pass { PixelShader = compile ps_3_0 brightpass(); }
    pass { PixelShader = compile ps_3_0 warpfx(); }
}
