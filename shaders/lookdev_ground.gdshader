shader_type spatial;
render_mode cull_back;

// Look-dev ground: layered wet-north materials from noise alone (no textures
// yet - this is the floor of what it'll look like, not the ceiling).
// Moss/grass on the flats, peaty dark in the hollows, scree and wet rock on
// slopes, rain-dark gravel where UV.x says the pad is. Everything slightly
// wet: low roughness in the hollows, puddle glints on the pad.

varying vec3 wpos;
varying vec3 wnorm;
varying float gravel;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	gravel = UV.x;
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

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	vec3 n = normalize(wnorm);
	float up = clamp(n.y, 0.0, 1.0);
	vec2 p = wpos.xz;

	float macro = fbm(p * 0.012);           // big colour drift
	float meso = fbm(p * 0.09);             // clumps
	float micro = vnoise(p * 1.7);          // grain
	float fine = vnoise(p * 6.3);           // pebbles / blades

	// --- materials ----------------------------------------------------------
	// moss/grass: olive, patchy, lighter where thin over rock
	vec3 moss = lin(mix(vec3(0.29, 0.36, 0.17), vec3(0.45, 0.44, 0.20), meso));
	moss = mix(moss, lin(vec3(0.52, 0.45, 0.22)), smoothstep(0.6, 0.85, fbm(p * 0.05 + 7.0)) * 0.6);
	moss *= 0.75 + 0.4 * micro;
	// peat in the hollows: dark, wet, rich
	vec3 peat = lin(vec3(0.19, 0.15, 0.10)) * (0.8 + 0.3 * meso);
	// rock and scree on slopes: cold grey, striated
	float strata = 0.8 + 0.3 * vnoise(vec2(wpos.y * 2.2, dot(p, vec2(0.3))));
	vec3 rock = lin(mix(vec3(0.30, 0.30, 0.31), vec3(0.42, 0.41, 0.39), micro)) * strata;
	// rain-dark gravel: blue-grey, pebbly
	vec3 grav = lin(mix(vec3(0.26, 0.27, 0.28), vec3(0.38, 0.38, 0.37), fine));
	grav *= 0.85 + 0.25 * meso;

	// --- blending ------------------------------------------------------------
	float hollow = smoothstep(1.2, -1.6, wpos.y + (macro - 0.5) * 2.0);   // low ground goes peaty
	float slope = smoothstep(0.93, 0.78, up + (micro - 0.5) * 0.06);      // steep goes rocky
	vec3 col = mix(moss, peat, hollow * 0.8);
	col = mix(col, rock, slope);
	col = mix(col, grav, gravel);

	// wetness: hollows and the pad hold water; everything has had rain
	float puddle = smoothstep(0.78, 0.9, fbm(p * 0.33 + 3.0)) * gravel;
	float wet = clamp(0.35 + hollow * 0.4 + gravel * 0.25 + puddle, 0.0, 1.0);
	col *= 1.0 - 0.18 * wet;

	ALBEDO = col;
	ROUGHNESS = clamp(mix(0.97, 0.72, wet) - 0.45 * puddle, 0.25, 1.0);
	SPECULAR = 0.08 + 0.10 * wet + 0.30 * puddle;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
