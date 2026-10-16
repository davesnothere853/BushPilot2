shader_type spatial;
render_mode cull_back;

// Gerstner-wave water: several wave trains summed - swell, wind chop and
// ripple - displacing the surface in the vertex stage, with analytic
// normals, crest foam, depth tinting and a fresnel sky response.
// The SAME wave set is computed on the CPU (water.gd surface_height) so
// floats and hulls ride exactly what you see.
//
// Wave uniforms: xy = direction (unit), z = steepness 0..1, w = wavelength m.

uniform vec4 wave_a = vec4(1.0, 0.0, 0.35, 14.0);
uniform vec4 wave_b = vec4(0.84, 0.54, 0.30, 9.0);
uniform vec4 wave_c = vec4(0.93, -0.37, 0.25, 5.5);
uniform vec4 wave_d = vec4(0.58, 0.81, 0.22, 3.2);
uniform vec4 wave_e = vec4(-0.26, 0.97, 0.18, 1.7);
uniform float amp_scale = 1.0;          // overall sea state (pond calm ~0.25)
uniform float foam_amount = 0.6;
uniform vec3 deep_color : source_color = vec3(0.045, 0.075, 0.08);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.14, 0.12);
uniform float time_scale = 1.0;

varying vec3 wpos;
varying float crest;      // how compressed the surface is here (foam driver)

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

// One Gerstner wave's contribution to position, and its derivatives.
vec3 gerstner(vec4 w, vec2 p, float t, inout vec3 tang, inout vec3 binorm) {
	float k = TAU / w.w;
	float c = sqrt(9.8 / k);              // deep-water speed
	vec2 d = normalize(w.xy);
	float f = k * (dot(d, p) - c * t);
	float a = w.z / k * amp_scale;
	float sf = sin(f);
	float cf = cos(f);
	tang += vec3(-d.x * d.x * w.z * amp_scale * sf, d.x * w.z * amp_scale * cf, -d.x * d.y * w.z * amp_scale * sf);
	binorm += vec3(-d.x * d.y * w.z * amp_scale * sf, d.y * w.z * amp_scale * cf, -d.y * d.y * w.z * amp_scale * sf);
	return vec3(d.x * a * cf, a * sf, d.y * a * cf);
}

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = base.xz;
	float t = TIME * time_scale;
	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 binorm = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	disp += gerstner(wave_a, p, t, tang, binorm);
	disp += gerstner(wave_b, p, t, tang, binorm);
	disp += gerstner(wave_c, p, t, tang, binorm);
	disp += gerstner(wave_d, p, t, tang, binorm);
	disp += gerstner(wave_e, p, t, tang, binorm);
	VERTEX += disp;
	vec3 n = normalize(cross(binorm, tang));
	NORMAL = n;
	wpos = base + disp;
	// Crests squeeze the surface horizontally: that's where foam lives.
	crest = clamp(1.0 - (tang.x + binorm.z) * 0.5, 0.0, 1.0) + disp.y * 1.4;
}

void fragment() {
	vec3 col = mix(deep_color, shallow_color, 0.35 + 0.3 * vnoise(wpos.xz * 0.11));
	// Crest foam: ragged, noisy, only where the wave is actually breaking.
	float fo = smoothstep(0.55, 0.95, crest * foam_amount + 0.35 * vnoise(wpos.xz * 1.9 + vec2(TIME * 0.25, 0.0)) - 0.25);
	col = mix(col, vec3(0.75, 0.78, 0.77), fo * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.5, fo);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
