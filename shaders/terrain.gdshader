shader_type spatial;
render_mode cull_back;

// Smooth-shaded terrain. Colour comes from height, slope, season and the forest
// density stored in the vertex colour, broken up by noise at several scales so
// the ground reads as grass, moss, lichen, gravel and layered rock. Close to
// the camera the surface gets small bumps lit by the sun. Runways are painted
// here too, so they follow the ground exactly and never flicker against it.

uniform float snow_line = 1350.0;
uniform float snow_cover = 0.0;
uniform vec3 col_grass : source_color = vec3(0.23, 0.32, 0.15);
uniform vec3 col_tundra : source_color = vec3(0.42, 0.42, 0.25);
uniform vec3 col_forest : source_color = vec3(0.10, 0.20, 0.10);
uniform vec3 col_bog : source_color = vec3(0.42, 0.38, 0.24);
uniform vec3 col_burn : source_color = vec3(0.33, 0.30, 0.27);
uniform vec3 col_fireweed : source_color = vec3(0.46, 0.30, 0.36);
uniform vec3 col_rock : source_color = vec3(0.40, 0.38, 0.36);
uniform vec3 col_shore : source_color = vec3(0.55, 0.52, 0.46);
uniform vec3 col_snow : source_color = vec3(0.88, 0.90, 0.94);
uniform float detail_distance = 700.0;

uniform int strip_count = 0;
uniform vec4 strip_a[16];   // centre x, centre z, direction x, direction z
uniform vec4 strip_b[16];   // half length, half width, surface type, 1 for a bush strip you cut

// Dug ground: one texel per 24 m tile; where it's set, dig_site.gd draws the ground instead.
uniform sampler2D dig_mask : filter_nearest;
uniform vec2 dig_origin = vec2(0.0);
uniform float dig_cell = 24.0;
uniform int dig_on = 0;

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 vdata;
varying vec2 veco;    // old burn, creek

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdata = COLOR.rgb;
	veco = vec2(COLOR.a, UV.x);
}

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
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
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm3(vec2 p) {
	float s = 0.5 * vnoise(p);
	s += 0.25 * vnoise(p * 2.03 + 17.1);
	s += 0.125 * vnoise(p * 4.07 + 3.7);
	return s / 0.875;
}

// Small bumps: grass tussocks and stones up close.
float bumps(vec2 p) {
	return 0.6 * vnoise(p * 0.55) + 0.4 * vnoise(p * 1.9 + 5.0);
}

void fragment() {
	if (dig_on == 1) {
		ivec2 t = ivec2(floor((wpos.xz - dig_origin) / dig_cell));
		ivec2 sz = textureSize(dig_mask, 0);
		if (t.x >= 0 && t.y >= 0 && t.x < sz.x && t.y < sz.y && texelFetch(dig_mask, t, 0).r > 0.5) {
			discard;
		}
	}
	vec3 n = normalize(wnorm);
	float up = n.y;
	vec2 p = wpos.xz;
	float h = wpos.y;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float forest = vdata.r;
	float vary = vdata.g;

	// Noise at three scales: big patches, mid clumps, fine grain.
	float patch = fbm3(p / 70.0);
	float clump = fbm3(p / 11.0);
	float grain = vnoise(p * 0.9);
	float far_fade = 1.0 - smoothstep(1500.0, 6000.0, dist);

	// Grass and tundra with moss, dry patches and lichen.
	vec3 grass = col_grass * mix(vec3(0.82, 0.90, 0.80), vec3(1.25, 1.12, 0.78), patch);
	grass = mix(grass, grass * vec3(0.75, 0.85, 0.70), smoothstep(0.55, 0.8, clump) * far_fade);
	vec3 tundra = col_tundra * mix(vec3(0.85, 0.85, 0.80), vec3(1.18, 1.05, 0.86), clump);
	tundra = mix(tundra, tundra * vec3(1.25, 0.88, 0.70), smoothstep(0.6, 0.85, patch) * 0.6);   // rusty dwarf birch
	vec3 col = mix(grass, tundra, smoothstep(220.0, 640.0, h + (vary - 0.5) * 220.0 + (patch - 0.5) * 120.0));
	float bog = vdata.b;
	float burnt = veco.x;
	float creek = veco.y;
	// Creek bottoms: lusher, darker green.
	col = mix(col, col_grass * vec3(0.80, 0.98, 0.78), smoothstep(0.3, 0.9, creek) * 0.45);
	// Muskeg: olive and rust sphagnum, sedge, and small dark ponds.
	// Sphagnum and sedge: olive, with ochre and rust drifts and darker wet hollows.
	vec3 bogc = col_bog * mix(vec3(0.88, 0.96, 0.84), vec3(1.14, 0.94, 0.78), smoothstep(0.4, 0.85, clump));
	bogc = mix(bogc, col_bog * vec3(1.08, 0.80, 0.66), smoothstep(0.6, 0.85, fbm3(p / 18.0 + 3.0)) * 0.5);
	bogc *= 0.82 + 0.25 * smoothstep(0.2, 0.7, fbm3(p / 4.0));
	bogc *= 0.9 + 0.2 * patch;
	float bogw = smoothstep(0.3, 0.7, bog + (patch - 0.5) * 0.35);
	float pond = smoothstep(0.80, 0.86, fbm3(p / 9.0 + 41.0)) * smoothstep(0.55, 0.85, bog) * far_fade;
	bogc = mix(bogc, vec3(0.025, 0.035, 0.04), pond * 0.9);
	col = mix(col, bogc, bogw);
	// Old burns: grey ash ground with drifts of fireweed.
	vec3 burnc = col_burn * (0.85 + 0.3 * clump);
	burnc = mix(burnc, col_fireweed, smoothstep(0.5, 0.8, fbm3(p / 25.0 + 7.0)) * 0.3);
	col = mix(col, burnc, smoothstep(0.35, 0.7, burnt + (patch - 0.5) * 0.25));
	col = mix(col, col_forest * (0.85 + 0.3 * clump), forest * 0.85);
	col = mix(col_shore * (0.85 + 0.3 * grain), col, smoothstep(1.0, 4.5, h + (vary - 0.5) * 1.5));

	// Rock on steep ground and high up: layered, streaked downhill.
	float strata = 0.5 + 0.5 * sin(h * 0.14 + fbm3(p / 40.0) * 5.0);
	strata = mix(strata, 0.5, smoothstep(600.0, 2500.0, dist));
	vec3 rock = col_rock * (0.70 + 0.35 * strata + 0.25 * (clump - 0.5)) * (0.9 + 0.2 * vary);
	float rocky = 1.0 - smoothstep(0.62 + (patch - 0.5) * 0.15, 0.82, up);
	rocky = max(rocky, smoothstep(950.0, 1500.0, h) * (0.45 + 0.35 * patch));
	col = mix(col, rock, rocky);

	// Creeks: where enough ground drains through (the same line the gold pan
	// works in), running water shows - a damp gravel margin, then the stream,
	// shallow at the lip and tea-dark in the middle, with a moving glitter.
	// The creek field is a broad band (the willows grow all through it). The
	// running water is a winding thread a few metres wide - the ridge line of
	// a noise field - with the odd beaver pond, only inside that band.
	float tn = fbm3(p / 26.0 + 9.0);
	float thread = 1.0 - abs(tn - 0.5) * 2.0;
	float pool = smoothstep(0.82, 0.90, fbm3(p / 9.0 + 23.0));
	float gate = smoothstep(0.55, 0.85, creek) * smoothstep(0.35, 0.6, up);
	float wet = max(smoothstep(0.70, 0.87, thread), smoothstep(0.76, 0.84, fbm3(p / 9.0 + 23.0))) * gate;
	float water = max(smoothstep(0.87, 0.94, thread), pool) * gate;
	if (wet > 0.001) {
		vec3 damp = lin(vec3(0.33, 0.30, 0.25)) * (0.80 + 0.30 * grain);
		col = mix(col, damp, wet * (1.0 - water) * 0.65);
	}
	if (water > 0.001) {
		float rip = 0.6 * vnoise(p * 2.6 + vec2(TIME * 0.8, TIME * 0.45))
			+ 0.4 * vnoise(p * 6.1 - vec2(TIME * 1.4, TIME * 0.2));
		vec3 deep = mix(vec3(0.020, 0.040, 0.038), vec3(0.050, 0.085, 0.075), rip);
		vec3 shallow = col * vec3(0.52, 0.62, 0.60) + vec3(0.01, 0.02, 0.02) * rip;
		vec3 wcol = mix(shallow, deep, max(smoothstep(0.92, 0.985, thread), pool));
		col = mix(col, wcol, water * 0.92);
		// The surface wobbles, so the sun glitters off it.
		float e2 = 0.6;
		float r0 = vnoise(p * 2.6 + vec2(TIME * 0.8, TIME * 0.45));
		float rx = vnoise((p + vec2(e2, 0.0)) * 2.6 + vec2(TIME * 0.8, TIME * 0.45));
		float rz = vnoise((p + vec2(0.0, e2)) * 2.6 + vec2(TIME * 0.8, TIME * 0.45));
		n = normalize(mix(n, vec3(0.0, 1.0, 0.0) - vec3(rx - r0, 0.0, rz - r0) * 1.4, water));
	}

	// Snow: lies on flatter ground, thins out on steep faces and wind-scoured ridges.
	float line = snow_line + (vary - 0.5) * 240.0 + (patch - 0.5) * 160.0;
	float snow = smoothstep(line - 70.0, line + 70.0, h) * smoothstep(0.45 + 0.1 * clump, 0.72, up);
	snow = max(snow, snow_cover * smoothstep(0.40, 0.66, up + (clump - 0.5) * 0.12) * (1.0 - forest * 0.4));
	col = mix(col, col_snow * (0.96 + 0.06 * grain), snow);

	col *= 0.94 + 0.12 * grain * far_fade;

	// Runways
	float on_strip = 0.0;
	for (int i = 0; i < strip_count; i++) {
		vec2 d = p - strip_a[i].xy;
		vec2 dir = strip_a[i].zw;
		float along = dot(d, dir);
		float across = dot(d, vec2(-dir.y, dir.x));
		float hl = strip_b[i].x;
		float hw = strip_b[i].y;
		float inside = (1.0 - smoothstep(hl - 0.5, hl + 1.5, abs(along))) * (1.0 - smoothstep(hw - 0.5, hw + 1.5, abs(across)));
		if (inside > 0.001) {
			int kind = int(strip_b[i].z + 0.5);
			vec3 sc = lin(vec3(0.43, 0.41, 0.37)) * (0.85 + 0.3 * clump);            // gravel
			if (kind == 2) { sc = col_grass * (1.35 + 0.25 * clump) + vec3(0.012, 0.016, 0.0); }   // mown grass
			if (kind == 3) { sc = lin(vec3(0.46, 0.37, 0.27)) * (0.85 + 0.3 * clump); }    // dirt
			sc *= 0.92 + 0.16 * grain;
			// Wheel tracks down the middle.
			float track = 1.0 - smoothstep(0.35, 0.9, abs(abs(across) - 1.25));
			sc *= 1.0 - 0.16 * track;
			// Pale band at each threshold.
			float ends = smoothstep(hl - 4.0, hl - 3.2, abs(along));
			sc = mix(sc, lin(vec3(0.80, 0.79, 0.74)), ends * 0.6 * (1.0 - strip_b[i].w));
			float on_snow = max(snow_cover, smoothstep(line - 70.0, line + 70.0, h));
			sc = mix(sc, col_snow * vec3(0.80, 0.84, 0.90) * (0.94 + 0.10 * grain) * (1.0 - 0.10 * track), on_snow);
			col = mix(col, sc, inside);
			on_strip = max(on_strip, inside);
		}
	}

	// Surface bumps close in, stronger on rock and rough ground, gentle on strips and snow.
	float near = 1.0 - smoothstep(120.0, detail_distance, dist);
	if (near > 0.0) {
		float e = 0.35;
		float b0 = bumps(p);
		float bx = bumps(p + vec2(e, 0.0));
		float bz = bumps(p + vec2(0.0, e));
		float strength = mix(0.55, 1.3, rocky) * (1.0 - 0.7 * snow) * (1.0 - 0.75 * on_strip) * near;
		vec3 g = vec3(bx - b0, 0.0, bz - b0) / e;
		n = normalize(n - g * strength);
	}

	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.82, rocky) - 0.25 * snow - 0.8 * pond * (1.0 - snow) - 0.85 * water * (1.0 - snow);
	SPECULAR = 0.25 + 0.2 * snow + 0.3 * water;
}
