// ============================================================================
//  Futuristic hacker CRT  -  Windows Terminal pixel shader
//  Curvature + phosphor mask + travelling scan beam + scanlines + bloom.
//  Tuned to stay readable. Entry point: main().
//
//  Apply per-profile in settings.json:
//    "experimental.pixelShaderPath": "C:\\Users\\<you>\\.config\\shaders\\crt.hlsl"
// ============================================================================

Texture2D    shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings : register(b0)
{
    float  Time;        // seconds since start (animates)
    float  Scale;
    float2 Resolution;  // terminal size in pixels
    float4 Background;
};

// ---- tweakables -------------------------------------------------------------
static const float CURVATURE        = 0.045; // screen bend; 0 = flat
static const float SCANLINE_INT     = 0.07;  // horizontal scanline darkening
static const float MASK_STRENGTH    = 0.07;  // RGB phosphor stripes
static const float GLOW_STRENGTH     = 0.10; // soft bloom around bright text
static const float BEAM_STRENGTH    = 0.06;  // travelling scan beam brightness
static const float BEAM_SPEED       = 0.18;  // beam travel speed (screens/sec)
static const float VIGNETTE         = 0.16;  // edge darkening
static const float FLICKER          = 0.006; // brightness wobble
static const float WARM_TINT        = 0.06;  // slight amber/Gruvbox warmth
static const float OPACITY          = 1.0;   // content alpha; window transparency
                                             // is set by the profile "opacity"
// ----------------------------------------------------------------------------

// Barrel-distort the UV for CRT curvature.
float2 curve(float2 uv)
{
    uv = uv * 2.0 - 1.0;
    float2 off = abs(uv.yx) * CURVATURE;
    uv = uv + uv * off * off;
    return uv * 0.5 + 0.5;
}

// Cheap 5-tap blur for the glow.
float3 sampleGlow(float2 uv)
{
    float2 px = 1.5 / Resolution;
    float3 c  = shaderTexture.Sample(samplerState, uv).rgb;
    c += shaderTexture.Sample(samplerState, uv + float2( px.x, 0)).rgb;
    c += shaderTexture.Sample(samplerState, uv + float2(-px.x, 0)).rgb;
    c += shaderTexture.Sample(samplerState, uv + float2(0,  px.y)).rgb;
    c += shaderTexture.Sample(samplerState, uv + float2(0, -px.y)).rgb;
    return c / 5.0;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    // --- curvature ---
    float2 uv = curve(tex);

    // outside the curved screen -> fully transparent bezel (corners show through)
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 0.0);

    float3 color = shaderTexture.Sample(samplerState, uv).rgb;

    // --- soft glow / phosphor bloom ---
    float3 glow = sampleGlow(uv);
    color += glow * GLOW_STRENGTH;

    // --- travelling scan beam: a soft bright band sweeping down the screen ---
    float beamPos = frac(Time * BEAM_SPEED);
    float dist    = abs(uv.y - beamPos);
    dist          = min(dist, 1.0 - dist);            // wrap around
    float beam    = exp(-dist * dist * 1200.0);       // tight soft band
    color += beam * BEAM_STRENGTH;

    // --- scanlines ---
    float s    = sin(uv.y * Resolution.y * 3.14159);
    float scan = 1.0 - SCANLINE_INT * (0.5 + 0.5 * s * s);
    color *= scan;

    // --- RGB phosphor mask (aperture grille) ---
    float m = frac(pos.x / 3.0);
    float3 mask = float3(1.0 - MASK_STRENGTH, 1.0 - MASK_STRENGTH, 1.0 - MASK_STRENGTH);
    if (m < 0.333)      mask.r = 1.0 + MASK_STRENGTH;
    else if (m < 0.666) mask.g = 1.0 + MASK_STRENGTH;
    else                mask.b = 1.0 + MASK_STRENGTH;
    color *= mask;

    // --- slight warm tint (amber / Gruvbox direction) ---
    color *= float3(1.0 + WARM_TINT, 1.0 + WARM_TINT * 0.4, 1.0 - WARM_TINT * 0.5);

    // --- subtle flicker ---
    color *= 1.0 - FLICKER * (0.5 + 0.5 * sin(Time * 6.2831 * 9.0));

    // --- gentle vignette ---
    float2 d = uv - 0.5;
    color *= saturate(1.0 - VIGNETTE * dot(d, d) * 3.5);

    return float4(color, OPACITY);
}
