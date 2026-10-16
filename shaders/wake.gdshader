shader_type spatial;
// Foam on the water: each patch is a soft oval of white that breaks up into
// lacy streaks and fades as it ages. INSTANCE_CUSTOM: r age 0..1, g strength, b seed.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying vec4 cd;
varying vec3 wp;

void vertex() {
	cd = INSTANCE_CUSTOM;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float age = cd.r;
	float edge = 1.0 - smoothstep(0.45, 1.0, length(uv));
	// Streaky foam: stretched along the patch (the way the water moved).
	vec2 q = wp.xz;
	float n = noise(q * 2.3 + cd.b * 31.0) * 0.55 + noise(q * 7.0 - cd.b * 13.0) * 0.3 + noise(q * 19.0) * 0.15;
	float lace = smoothstep(0.30 + 0.35 * age, 0.55 + 0.35 * age, n);
	float fresh = 1.0 - smoothstep(0.0, 0.25, age);
	float a = edge * mix(lace, 1.0, fresh * 0.7) * (1.0 - age) * (1.0 - age) * cd.g;
	ALBEDO = vec3(0.90, 0.93, 0.94);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	ALPHA = clamp(a, 0.0, 0.92);
}
