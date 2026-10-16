shader_type spatial;
render_mode cull_back;

// Diggable ground. Undisturbed, it runs the very same sums as the island's
// terrain shader, so a tile is indistinguishable from the ground around it:
// grass, tundra, muskeg, burns, forest floor, creek water and snow all carry
// straight across. Only where the surface has been cut or piled does the
// soil show: topsoil, grey overburden, rusty pay gravel, then bedrock.
//
// Per vertex: COLOR = (forest, vary, bog, burn); UV = (creek, dug depth);
// CUSTOM0 = (pay top, bedrock depth, grade g/m3, 0).

uniform float snow_line = 1350.0;
uniform float snow_cover = 0.0;
uniform vec3 col_grass : source_color = vec3(0.23, 0.32, 0.15);
uniform vec3 col_tundra : source_color = vec3(0.42, 0.42, 0.25);
uniform vec3 col_forest : source_color = vec3(0.10, 0.20, 0.10);
uniform vec3 col_bog : source_color = vec3(0.42, 0.38, 0.24);
uniform vec3 col_burn : source_color = vec3(0.33, 0.30, 0.27);
uniform vec3 col_fireweed : source_color = vec3(0.46, 0.30, 0.36);
uniform vec3 col_shore : source_color = vec3(0.55, 0.52, 0.46);
uniform vec3 col_snow : source_color = vec3(0.88, 0.90, 0.94);

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 vdata;     // forest, vary, bog, burn
varying vec2 vuv;       // creek, dug depth
varying vec4 vgeo;      // pay top, bedrock, grade, -

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdata = COLOR;
	vuv = UV;
	vgeo = CUSTOM0;
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

void fragment() {
	vec3 n = normalize(wnorm);
	float up = n.y;
	vec2 p = wpos.xz;
	float h = wpos.y;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float forest = vdata.r;
	float vary = vdata.g;
	float bog = vdata.b;
	float burnt = vdata.a;
	float creek = vuv.x;
	float dug = vuv.y;             // metres below the old surface (negative: a pile)

	float patch = fbm3(p / 70.0);
	float clump = fbm3(p / 11.0);
	float grain = vnoise(p * 0.9);
	float far_fade = 1.0 - smoothstep(1500.0, 6000.0, dist);

	// --- the undisturbed ground, exactly as the island draws it ------------------
	vec3 grass = col_grass * mix(vec3(0.82, 0.90, 0.80), vec3(1.25, 1.12, 0.78), patch);
	grass = mix(grass, grass * vec3(0.75, 0.85, 0.70), smoothstep(0.55, 0.8, clump) * far_fade);
	vec3 tundra = col_tundra * mix(vec3(0.85, 0.85, 0.80), vec3(1.18, 1.05, 0.86), clump);
	tundra = mix(tundra, tundra * vec3(1.25, 0.88, 0.70), smoothstep(0.6, 0.85, patch) * 0.6);
	vec3 col = mix(grass, tundra, smoothstep(220.0, 640.0, h + (vary - 0.5) * 220.0 + (patch - 0.5) * 120.0));
	col = mix(col, col_grass * vec3(0.80, 0.98, 0.78), smoothstep(0.3, 0.9, creek) * 0.45);
	vec3 bogc = col_bog * mix(vec3(0.88, 0.96, 0.84), vec3(1.14, 0.94, 0.78), smoothstep(0.4, 0.85, clump));
	bogc = mix(bogc, col_bog * vec3(1.08, 0.80, 0.66), smoothstep(0.6, 0.85, fbm3(p / 18.0 + 3.0)) * 0.5);
	bogc *= 0.82 + 0.25 * smoothstep(0.2, 0.7, fbm3(p / 4.0));
	bogc *= 0.9 + 0.2 * patch;
	float bogw = smoothstep(0.3, 0.7, bog + (patch - 0.5) * 0.35);
	col = mix(col, bogc, bogw);
	vec3 burnc = col_burn * (0.85 + 0.3 * clump);
	burnc = mix(burnc, col_fireweed, smoothstep(0.5, 0.8, fbm3(p / 25.0 + 7.0)) * 0.3);
	col = mix(col, burnc, smoothstep(0.35, 0.7, burnt + (patch - 0.5) * 0.25));
	col = mix(col, col_forest * (0.85 + 0.3 * clump), forest * 0.85);
	col = mix(col_shore * (0.85 + 0.3 * grain), col, smoothstep(1.0, 4.5, h + (vary - 0.5) * 1.5));

	// Creek water, the same winding thread as the terrain draws.
	float tn = fbm3(p / 26.0 + 9.0);
	float thread = 1.0 - abs(tn - 0.5) * 2.0;
	float pool = smoothstep(0.82, 0.90, fbm3(p / 9.0 + 23.0));
	float gate = smoothstep(0.55, 0.85, creek) * smoothstep(0.35, 0.6, up);
	float wet = max(smoothstep(0.70, 0.87, thread), smoothstep(0.76, 0.84, fbm3(p / 9.0 + 23.0))) * gate;
	float water = max(smoothstep(0.87, 0.94, thread), pool) * gate;
	// Dug-out ground drains: the thread doesn't paint the pit floor.
	wet *= 1.0 - smoothstep(0.1, 0.3, dug);
	water *= 1.0 - smoothstep(0.1, 0.3, dug);
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
	}

	// --- the cut: soil layers where the ground has been dug or piled -------------
	float soil_grain = 0.75 + 0.35 * vnoise(p * 2.1);
	vec3 c_soil = lin(vec3(0.36, 0.27, 0.18)) * soil_grain;
	vec3 c_over = lin(vec3(0.52, 0.47, 0.38)) * soil_grain;
	vec3 c_pay = lin(mix(vec3(0.55, 0.38, 0.20), vec3(0.62, 0.42, 0.15), clamp(vgeo.z / 40.0, 0.0, 1.0))) * soil_grain;
	vec3 c_rock = lin(vec3(0.32, 0.32, 0.33)) * (0.8 + 0.3 * clump);
	vec3 c_spoil = lin(vec3(0.45, 0.37, 0.27)) * soil_grain;
	vec3 cut = mix(c_soil, c_over, smoothstep(0.15, 0.45, dug));
	cut = mix(cut, c_over, smoothstep(0.3, max(vgeo.x * 0.6, 0.35), dug));
	cut = mix(cut, c_pay, smoothstep(vgeo.x - 0.06, vgeo.x + 0.08, dug));
	cut = mix(cut, c_rock, smoothstep(vgeo.y - 0.05, vgeo.y + 0.02, dug));
	// Piled spoil reads as loose dirt; the cut blends in over the first hand's width.
	col = mix(col, c_spoil, smoothstep(-0.05, -0.18, dug));
	col = mix(col, cut, smoothstep(0.03, 0.14, dug));

	// Snow lies over everything undisturbed; fresh workings stay dark.
	float line = snow_line + (vary - 0.5) * 240.0 + (patch - 0.5) * 160.0;
	float snow = smoothstep(line - 70.0, line + 70.0, h) * smoothstep(0.45 + 0.1 * clump, 0.72, up);
	snow = max(snow, snow_cover * smoothstep(0.40, 0.66, up + (clump - 0.5) * 0.12) * (1.0 - forest * 0.4));
	snow *= 1.0 - smoothstep(0.05, 0.25, abs(dug));
	col = mix(col, col_snow * (0.96 + 0.06 * grain), snow);

	col *= 0.94 + 0.12 * grain * far_fade;

	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = 0.95 - 0.25 * snow - 0.85 * water * (1.0 - snow);
	SPECULAR = 0.25 + 0.2 * snow + 0.3 * water;
}
