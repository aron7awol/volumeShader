// $MinimumShaderProfile: ps_3_0
// Highlight out-of-volume colors

//PQ constants
const static float m1 = 2610.0 / 16384;
const static float m2 = 2523.0 / 32;
const static float m1inv = 16384 / 2610.0;
const static float m2inv = 32 / 2523.0;
const static float c1 = 3424 / 4096.0;
const static float c2 = 2413 / 128.0;
const static float c3 = 2392 / 128.0;

//Convert from linear 2020 RGB to XYZ
const static float3x3 RGB_2020_2_XYZ = {
     0.6369580,  0.1446169,  0.1688810,
     0.2627002,  0.6779981,  0.0593017,
     0.0000000,  0.0280727,  1.0609851
};

//Convert from XYZ to linear 2020 RGB
const static float3x3 XYZ_2_2020_RGB = {
     1.7166512, -0.3556708, -0.2533663,
    -0.6666844,  1.6164812,  0.0157685,
     0.0176399, -0.0427706,  0.9421031
};

//Convert from linear P3 RGB to XYZ
const static float3x3 P3_RGB_2_XYZ = {
     0.4865709,  0.2656677,  0.1982173,
     0.2289746,  0.6917385,  0.0792869,
     0.0000000,  0.0451134,  1.0439444
};

//Convert from XYZ to linear P3 RGB
const static float3x3 XYZ_2_P3_RGB = {
     2.4934969, -0.9313836, -0.4027108,
    -0.8294890,  1.7626641,  0.0236247,
     0.0358458, -0.0761724,  0.9568845
};

//Convert from linear 709 RGB to XYZ
const static float3x3 RGB_709_2_XYZ = {
     0.4123908,  0.3575843,  0.1804808,
     0.2126390,  0.7151687,  0.0721923,
     0.0193308,  0.1191948,  0.9505322
};

//Convert from XYZ to linear 709 RGB
const static float3x3 XYZ_2_709_RGB = {
     3.2409699, -1.5373832, -0.4986108,
    -0.9692436,  1.8759675,  0.0415551,
     0.0556301, -0.2039770,  1.0569715
};

// P3 primaries
const static float2 r = {0.68, 0.32};
const static float2 g = {0.265, 0.69};
const static float2 b = {0.15, 0.06};

const static float eps = 0.00001;

const static float relP3lumr = 0.2290628;
const static float relP3lumg = 0.6917500;
const static float relP3lumb = 0.0791871;

const static float maxP3r = 86.0 / 10000; 
const static float maxP3g = 301.0 / 10000; 
const static float maxP3b = 33.0 / 10000;
const static float maxP3rgb = maxP3r + maxP3g + maxP3b;
const static float maxr = maxP3r / relP3lumr;
const static float maxg = maxP3g / relP3lumg;
const static float maxb = maxP3b / relP3lumb;

sampler s0;
 
// Convert PQ to linear RGB
float3 pq_to_lin(float3 pq) { 
  float3 p = pow(pq, m2inv);
  float3 d = max(p - c1, 0) / (c2 - c3 * p);
  return pow(d, m1inv);
}

// Convert linear RGB to PQ
float3 lin_to_pq(float3 lin) {
  float3 y = lin; 
  float3 p = (c1 + c2 * pow(y, m1)) / (1 + c3 * pow(y, m1));
  return pow(p, m2);
}

// Convert linear 2020 RGB to XYZ
float3 rgb_2020_to_xyz(float3 rgb) {
    return mul(RGB_2020_2_XYZ, rgb);
}

// Convert XYZ to linear 2020 RGB
float3 xyz_to_2020_rgb(float3 xyz) {
    return mul(XYZ_2_2020_RGB, xyz);
}

// Convert XYZ to linear smaller gamut RGB
float3 xyz_to_smaller_rgb(float3 xyz) {
    return mul(XYZ_2_P3_RGB, xyz);
}

// Convert linear smaller gamut RGB to XYZ
float3 smaller_rgb_to_xyz(float3 rgb) {
    return mul(P3_RGB_2_XYZ, rgb);
}

// Convert RGB to LMS
float3 rgb_to_lms(float3 rgb) {
    float L = (1688 * rgb.r + 2146 * rgb.g + 262 * rgb.b) / 4096;
    float M = (683 * rgb.r + 2951 * rgb.g + 462 * rgb.b) / 4096;
    float S = (99 * rgb.r + 309 * rgb.g + 3688 * rgb.b) / 4096;
    return float3(L, M, S);
}

// Convert PQ LMS to ITP
float3 pq_lms_to_itp(float3 lms) {
    float I = 0.5 * lms.x + 0.5 * lms.y;
    float T = (6610 * lms.x - 13613 * lms.y + 7003 * lms.z) / 8192;
    float P = (17933 * lms.x - 17390 * lms.y - 543 * lms.z) / 4096;
    return float3(I, T, P);
}

// Calculate dEITP
float dEITP(float3 ITP1, float3 ITP2) {
    return 720 * sqrt(pow(ITP1.x - ITP2.x, 2) + pow(ITP1.y - ITP2.y, 2) + pow(ITP1.z - ITP2.z, 2));
}

float4 main(float2 tex : TEXCOORD0) : COLOR {
  float4 c0 = tex2D(s0, tex);

  if (all(c0.rgb == 0)) return c0;    //skip black pixels

  float3 lin = pq_to_lin(c0.rgb);      //Convert PQ to linear
  float3 XYZ = rgb_2020_to_xyz(lin);   //Convert 2020 RGB to XYZ
  float3 SGpt = xyz_to_smaller_rgb(XYZ);   //Convert XYZ to smaller gamut RGB
  float3 cSGpt = saturate(SGpt);           //Clip to smaller gamut

  float whitelin = min(min(cSGpt.r, cSGpt.g), cSGpt.b); //Calc white subpixel lum
  float rlin = cSGpt.r - whitelin;
  float glin = cSGpt.g - whitelin;
  float blin = cSGpt.b - whitelin;

  if (((rlin <= maxr) && (glin <= maxg)  && (blin <= maxb) && all(SGpt == cSGpt)) || any(SGpt != cSGpt)) {
//  if (all((cSGpt.rgb - whitelin) <= maxrgb) && all(SGpt == cSGpt)) {
//  if ((all((cSGpt.rgb - whitelin) <= maxrgb) && all(SGpt == cSGpt)) || any(SGpt != cSGpt)) {
//  if (all(SGpt == cSGpt)) {
	float lum = lin.r * 0.2627 + lin.g * 0.678 + lin.b * 0.0593;
	float3 desat = lin_to_pq(float3(lum, lum, lum));
	return float4(desat.r, desat.g, desat.b, 1);
  }

  float scaledown = min(min(maxr / rlin, maxg / glin), maxb / blin);
  float3 sRGB = lin * scaledown;

// Highlight based on dEITP threshold  

  float3 lms2 = rgb_to_lms(sRGB);          //Convert 2020 RGB to LMS
  float3 PQlms2 = lin_to_pq(lms2);         //Smaller-gamut-clamped pixel in PQ LMS

  float3 lms1 = rgb_to_lms(lin);           //Convert 2020 RGB to LMS
  float3 PQlms1 = lin_to_pq(lms1);         //Original pixel in PQ LMS

  float dE = dEITP(pq_lms_to_itp(PQlms1), pq_lms_to_itp(PQlms2));   //Calc dEITP for original pixel vs clamped pixel

  if (dE < 9) {                                                     //Desat if dEITP < 1 (JND - Just Noticeable Difference)
	float lum = lin.r * 0.2627 + lin.g * 0.678 + lin.b * 0.0593;
	float3 desat = lin_to_pq(float3(lum, lum, lum));
	return float4(desat.r, desat.g, desat.b, 1);
  }

// Heatmap dE 2-7
//  if (dE < 2) return float4(0.5, 0.5, 0, 1); //yellow
//  if (dE < 3) return float4(0, 0.5, 0, 1);   //green
//  if (dE < 4) return float4(0, 0.5, 0.5, 1); //cyan
//  if (dE < 5) return float4(0, 0, 0.5, 1);   //blue
//  if (dE < 6) return float4(0.5, 0, 0.5, 1); //magenta
//  if (dE < 7) return float4(0.5, 0, 0, 1);   //red

  return c0;                                      // Leave pixel alone
}
