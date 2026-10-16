shader_type spatial;
render_mode cull_back;

// The proving-ground's one unified ground. Materials are layered from noise
// plus per-vertex zone weights written by ground.gd:
//   COLOR.r  gravel (runway, apron, pad)
//   COLOR.g  muskeg / bog peat
//   COLOR.b  sand (pond shore)
//   COLOR.a  rock zone (the knoll)
//   UV.x     wetness 0..1
//   UV.y     dug depth in metres (orig - current): exposes dirt, pay, bedrock
// Lessons burned in from look-dev: specular stays low, roughness high,
// albedo saturated enough to read under an overcast sky.

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 zone;
varying vec2 wd;      // wet, dug

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	zone = COLOR;
	wd = UV;
}

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

float fbm(vec2 p) {
	float s = 0.5 * vnoise(p);
	s += 0.25 * vnoise(p * 2.11 + 13.7);
	s += 0.125 * vnoise(p * 4.23 + 5.2);
	s += 0.0625 * vnoise(p * 8.3 + 9.1);
	return s / 0.9375;
}

uniform float outback = 0.0;   // 1 = the Outback map: red dirt, ironstone, dry grass
#define PAL(north, aus) mix(north, aus, outback)
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	vec3 n = normalize(wnorm);
	float up = clamp(n.y, 0.0, 1.0);
	vec2 p = wpos.xz;

	float meso = fbm(p * 0.09);
	float micro = vnoise(p * 1.7);
	float fine = vnoise(p * 6.3);

	// --- materials ---------------------------------------------------------
	// moss and low tundra grass, patchy olive
	vec3 moss = lin(mix(PAL(vec3(0.33, 0.40, 0.19), vec3(0.66, 0.36, 0.20)), PAL(vec3(0.50, 0.48, 0.22), vec3(0.74, 0.54, 0.30)), meso));
	moss = mix(moss, lin(PAL(vec3(0.52, 0.45, 0.22), vec3(0.80, 0.66, 0.38))), smoothstep(0.6, 0.85, fbm(p * 0.05 + 7.0)) * 0.6);
	moss *= 0.75 + 0.4 * micro;
	// Alaska tundra (DESIGN_NOTES 109): moss, pale lichen, rusty dwarf shrubs.
	vec3 tundra = lin(mix(vec3(0.42, 0.44, 0.25), vec3(0.47, 0.47, 0.28), meso));
	// subtle: a hint of pale lichen and rusty shrub, not big blotches
	tundra = mix(tundra, lin(vec3(0.58, 0.60, 0.46)), smoothstep(0.55, 0.85, fbm(p * 0.06 + 17.0)) * 0.30);
	tundra = mix(tundra, lin(vec3(0.46, 0.36, 0.24)), smoothstep(0.62, 0.9, fbm(p * 0.05 + 29.0)) * 0.22);
	moss = mix(tundra * (0.85 + 0.2 * meso), moss, outback);
	// peat: dark, wet, rich, with sedge-yellow tussock tops
	vec3 peat = lin(PAL(vec3(0.19, 0.15, 0.10), vec3(0.50, 0.24, 0.13))) * (0.8 + 0.3 * meso);
	vec3 sedge = lin(PAL(vec3(0.48, 0.42, 0.18), vec3(0.74, 0.60, 0.32))) * (0.8 + 0.3 * micro);
	float tussock = smoothstep(0.55, 0.8, vnoise(p * 0.9 + 31.0));
	vec3 bogmat = mix(peat, sedge, tussock * 0.65);
	// grey rock, striated, lichen-spotted
	float strata = 0.8 + 0.3 * vnoise(vec2(wpos.y * 2.2, dot(p, vec2(0.3))));
	vec3 rock = lin(mix(PAL(vec3(0.30, 0.30, 0.31), vec3(0.46, 0.22, 0.13)), PAL(vec3(0.42, 0.41, 0.39), vec3(0.60, 0.32, 0.19)), micro)) * strata;
	rock = mix(rock, lin(PAL(vec3(0.55, 0.52, 0.30), vec3(0.72, 0.48, 0.30))), smoothstep(0.75, 0.95, vnoise(p * 1.1 + 9.0)) * 0.35 * up);
	// rain-dark runway gravel
	vec3 grav = lin(mix(PAL(vec3(0.35, 0.355, 0.36), vec3(0.62, 0.33, 0.19)), PAL(vec3(0.50, 0.49, 0.47), vec3(0.74, 0.45, 0.27)), fine));
	grav *= 0.85 + 0.25 * meso;
	// pond-shore sand and silt
	vec3 sand = lin(mix(PAL(vec3(0.46, 0.40, 0.30), vec3(0.80, 0.54, 0.32)), PAL(vec3(0.58, 0.52, 0.40), vec3(0.88, 0.66, 0.42)), fine)) * (0.85 + 0.2 * meso);

	// --- natural blend -----------------------------------------------------
	float slope = smoothstep(0.93, 0.76, up + (micro - 0.5) * 0.06);
	vec3 col = mix(moss, bogmat, clamp(zone.g * (0.75 + 0.5 * meso), 0.0, 1.0));
	col = mix(col, sand, clamp(zone.b * (1.0 + (fine - 0.5) * 0.5), 0.0, 1.0));
	col = mix(col, rock, clamp(slope + zone.a * smoothstep(0.35, 0.75, vnoise(p * 0.5 + 3.0) + zone.a * 0.6), 0.0, 1.0));
	col = mix(col, grav, clamp(zone.r + (fine - 0.5) * 0.15 * zone.r, 0.0, 1.0));

	// --- dug ground: turf torn off, then brown dirt, orange pay, grey bedrock.
	// Heaped-up ground (negative depth) is loose dug spoil: brown all over.
	float dug = wd.y;
	float heap = max(-wd.y, 0.0);
	if (heap > 0.03) {
		vec3 spoil = lin(mix(PAL(vec3(0.34, 0.26, 0.17), vec3(0.56, 0.26, 0.14)), PAL(vec3(0.46, 0.36, 0.24), vec3(0.66, 0.36, 0.20)), micro));
		spoil *= 0.85 + 0.3 * fine;
		col = mix(col, spoil, smoothstep(0.03, 0.25, heap + (micro - 0.5) * 0.08));
	}
	if (dug > 0.03) {
		vec3 dirt = lin(mix(PAL(vec3(0.36, 0.27, 0.17), vec3(0.56, 0.26, 0.14)), PAL(vec3(0.47, 0.37, 0.25), vec3(0.66, 0.36, 0.20)), micro));
		vec3 pay = lin(mix(PAL(vec3(0.52, 0.39, 0.21), vec3(0.74, 0.52, 0.26)), PAL(vec3(0.62, 0.49, 0.28), vec3(0.82, 0.62, 0.32)), fine));
		vec3 bed = lin(mix(PAL(vec3(0.33, 0.33, 0.35), vec3(0.42, 0.30, 0.26)), PAL(vec3(0.45, 0.44, 0.44), vec3(0.54, 0.40, 0.34)), micro));
		vec3 cut = dirt;
		cut = mix(cut, pay, smoothstep(0.7, 1.3, dug));
		cut = mix(cut, bed, smoothstep(2.4, 3.2, dug));
		col = mix(col, cut, smoothstep(0.03, 0.22, dug + (micro - 0.5) * 0.1));
	}

	// --- wetness -----------------------------------------------------------
	float puddle = smoothstep(0.80, 0.92, fbm(p * 0.33 + 3.0)) * max(zone.r, zone.g * 0.7);
	float wet = clamp(wd.x + 0.25 * zone.g + puddle, 0.0, 1.0);
	col *= 1.0 - 0.18 * wet;

	ALBEDO = col;
	ROUGHNESS = clamp(mix(0.97, 0.72, wet) - 0.45 * puddle, 0.25, 1.0);
	SPECULAR = 0.08 + 0.10 * wet + 0.30 * puddle;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
