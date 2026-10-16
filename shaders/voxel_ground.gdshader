shader_type spatial;
render_mode cull_back;

// Smooth voxel ground (Transvoxel). Same materials as ground.gdshader, but
// every input comes from world position + textures instead of vertex data,
// because the voxel mesher only gives positions:
//   layers  r natural surface y, g pay-top depth, b bedrock depth, a gold grade
//   zones   r gravel (runway/apron/pad), g muskeg, b pond sand, a rock knoll
//   wetmap  r wetness
// Flat facet normals give the polyart look; cut faces show real layers -
// turf, brown dirt, rusty pay gravel, grey bedrock - so drift walls do too.

uniform sampler2D layers : filter_linear, repeat_disable;
uniform sampler2D zones : filter_linear, repeat_disable;
uniform sampler2D wetmap : filter_linear, repeat_disable;
uniform float sq = 180.0;
uniform float facet = 1.0;     // 1 = flat polyart facets, 0 = smooth shading
uniform float poly_noise = 0.35;  // 1 = the old speckled ground, 0 = flat polyart colour

varying vec3 wpos;

// Transvoxel LOD seams (set by the voxel engine)
uniform int u_transition_mask;
float tv_secondary(int idata) {
	int tm = u_transition_mask & 0xff;
	int cell_border = idata & 63;
	int vert_border = (idata >> 8) & 63;
	float t = float((tm & cell_border) != 0);
	t *= float((vert_border & ~tm) == 0);
	return t;
}
vec3 tv_position(vec3 v, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	vec3 pos = mix(v, fdata.xyz, tv_secondary(idata));
	int itr = (idata >> 16) & 0xff;
	pos *= float(itr == 0 || (itr & u_transition_mask) != 0);
	return pos;
}

void vertex() {
	VERTEX = tv_position(VERTEX, CUSTOM0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	return s / 0.875;
}
// 3D noise for cut faces: a drift wall is vertical, so anything sampled on
// x/z alone smears into straight up-and-down streaks.
float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), u.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), u.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}
// Stones set in the ground: nearest and second-nearest jittered cell centres.
// x = distance to the nearest, y = second - nearest (0 on the crack between
// two cells), z = that cell's random id.
vec3 stones3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				float h = hash31(i + g);
				vec3 o = vec3(h, hash31(i + g + 17.1), hash31(i + g + 41.7));
				float d = length(g + 0.15 + 0.7 * o - f);
				if (d < d1) { d2 = d1; d1 = d; id = h; }
				else if (d < d2) { d2 = d; }
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

// Quartz veins (veins.gd, DESIGN_NOTES 139). Mirrors Veins.at() exactly.
// Plain uniforms, set once in voxel_ground.setup() before any chunk copies
// the material: the veins are fixed for the world seed.
uniform sampler2D bp_veins : filter_nearest;
uniform float bp_vein_n = 0.0;
// x = 1 inside a vein (soft wall), y = grade g/t here, z = 0 middle .. 1 the wall
vec3 vein_at(vec3 p, float natural_y) {
	float depth = max(natural_y - p.y, 0.0);
	for (int i = 0; i < 8; i++) {
		if (float(i) >= bp_vein_n) { break; }
		vec4 a0 = texelFetch(bp_veins, ivec2(i, 0), 0);
		vec4 a1 = texelFetch(bp_veins, ivec2(i, 1), 0);
		float rx = p.x - a0.x;
		float rz = p.z - a0.y;
		float along = rx * cos(a0.z) + rz * sin(a0.z);
		float across = -rx * sin(a0.z) + rz * cos(a0.z);
		float hl = a1.y;
		if (abs(along) > hl) { continue; }
		float fi = float(i);
		float d = across - depth / tan(a1.x) + 0.25 * sin(along * 0.13 + fi * 2.3);
		float taper = 1.0 - smoothstep(hl * 0.7, hl, abs(along));
		float halfw = a0.w * 0.5 * (0.7 + 0.3 * sin(along * 0.37 + fi * 1.7)) * taper;
		if (abs(d) < halfw + 0.04) {
			float shoot = max(sin(along * 0.09 + fi * 0.7 + depth * 0.05), 0.0);
			return vec3(1.0 - smoothstep(halfw - 0.03, halfw + 0.03, abs(d)), a1.z * (0.15 + 0.85 * shoot * shoot), abs(d) / max(halfw, 0.01));
		}
	}
	return vec3(0.0);
}

uniform float outback = 0.0;
// Season settings are GLOBAL uniforms: the voxel engine copies this material
// for every chunk of ground, so a plain uniform changed later never reaches
// them (voxel_ground.gd ensure_globals / set_global).
global uniform float bp_rain;        // how soaked everything is by rain now (storm.gd): darker, glossy, puddles shine
global uniform float bp_mud_k;       // how wet the soft ground is this season (winter frozen .. spring break-up)
// Winter (DESIGN_NOTES 117): snow over everything undisturbed - thinner on
// steep faces and under the trees - and melted back where a fire's been.
global uniform float bp_snow_cover;
global uniform float bp_snow_line;
global uniform vec3 bp_col_snow;     // linear
global uniform sampler2D bp_melt : filter_linear, repeat_disable;   // r: 1 = melted bare (fire.gd)
global uniform sampler2D bp_wear : filter_linear, repeat_disable;   // r: torn / packed by tracks and tyres (wear.gd)
#define PAL(north, aus) mix(north, aus, outback)
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	vec3 n_flat = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 nv = normalize(mix(NORMAL, n_flat, facet));
	NORMAL = nv;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
	float up = clamp(n.y, 0.0, 1.0);
	vec2 p = wpos.xz;
	vec2 uv = clamp((p + sq) / (2.0 * sq), 0.0, 1.0);
	vec4 L = texture(layers, uv);
	vec4 zone = texture(zones, uv);
	float wetv = texture(wetmap, uv).r;

	// Polyart: broad flat patches (posterised), only a whisper of fine noise,
	// so the faceted shading carries the detail in the polyart style.
	float meso = floor(fbm(p * 0.07) * 5.0 + 0.5) / 5.0;
	float micro = mix(0.5, vnoise(p * 0.9), poly_noise);
	float fine = mix(0.5, vnoise(p * 3.1), poly_noise * 0.6);

	// --- surface materials (as ground.gdshader) ---------------------------
	vec3 moss = lin(mix(PAL(vec3(0.33, 0.40, 0.19), vec3(0.66, 0.36, 0.20)), PAL(vec3(0.50, 0.48, 0.22), vec3(0.74, 0.54, 0.30)), meso));
	moss = mix(moss, lin(PAL(vec3(0.52, 0.45, 0.22), vec3(0.80, 0.66, 0.38))), smoothstep(0.6, 0.85, fbm(p * 0.05 + 7.0)) * 0.6);
	moss *= 0.8 + 0.3 * micro;
	// Alaska tundra (DESIGN_NOTES 109): olive moss, big pale patches of
	// reindeer lichen, rusty drifts of dwarf birch and crowberry.
	vec3 tundra = lin(mix(vec3(0.42, 0.44, 0.25), vec3(0.47, 0.47, 0.28), meso));
	// subtle: a hint of pale lichen and rusty shrub, not big blotches
	tundra = mix(tundra, lin(vec3(0.58, 0.60, 0.46)), smoothstep(0.55, 0.85, fbm(p * 0.06 + 17.0)) * 0.30);
	tundra = mix(tundra, lin(vec3(0.46, 0.36, 0.24)), smoothstep(0.62, 0.9, fbm(p * 0.05 + 29.0)) * 0.22);
	tundra *= 0.92 + 0.12 * micro;
	moss = mix(tundra, moss, outback);
	vec3 peat = lin(PAL(vec3(0.19, 0.15, 0.10), vec3(0.50, 0.24, 0.13))) * (0.8 + 0.3 * meso);
	vec3 sedge = lin(PAL(vec3(0.48, 0.42, 0.18), vec3(0.74, 0.60, 0.32))) * (0.8 + 0.3 * micro);
	vec3 bogmat = mix(peat, sedge, smoothstep(0.55, 0.8, vnoise(p * 0.9 + 31.0)) * 0.65);
	float strata = 0.8 + 0.3 * vnoise(vec2(wpos.y * 2.2, dot(p, vec2(0.3))));
	vec3 rock = lin(mix(PAL(vec3(0.30, 0.30, 0.31), vec3(0.46, 0.22, 0.13)), PAL(vec3(0.42, 0.41, 0.39), vec3(0.60, 0.32, 0.19)), micro)) * strata;
	rock = mix(rock, lin(PAL(vec3(0.55, 0.52, 0.30), vec3(0.72, 0.48, 0.30))), smoothstep(0.75, 0.95, vnoise(p * 1.1 + 9.0)) * 0.35 * up);
	vec3 grav = lin(mix(PAL(vec3(0.35, 0.355, 0.36), vec3(0.62, 0.33, 0.19)), PAL(vec3(0.50, 0.49, 0.47), vec3(0.74, 0.45, 0.27)), fine)) * (0.85 + 0.25 * meso);
	vec3 sand = lin(mix(PAL(vec3(0.55, 0.54, 0.51), vec3(0.80, 0.54, 0.32)), PAL(vec3(0.68, 0.67, 0.63), vec3(0.88, 0.66, 0.42)), fine)) * (0.85 + 0.2 * meso);
	// creek gravel bars: grey cobbles, darker stones scattered through
	sand = mix(sand, lin(vec3(0.40, 0.39, 0.38)), step(0.7, vnoise(p * 4.0 + 13.0)) * 0.6 * (1.0 - outback));

	float slope = smoothstep(0.93, 0.76, up + (micro - 0.5) * 0.06);
	vec3 col = mix(moss, bogmat, clamp(zone.g * (0.75 + 0.5 * meso), 0.0, 1.0));
	col = mix(col, sand, clamp(zone.b * (1.0 + (fine - 0.5) * 0.5), 0.0, 1.0));
	col = mix(col, rock, clamp(slope + zone.a * smoothstep(0.35, 0.75, vnoise(p * 0.5 + 3.0) + zone.a * 0.6), 0.0, 1.0));
	col = mix(col, grav, clamp(zone.r + (fine - 0.5) * 0.15 * zone.r, 0.0, 1.0));

	// --- mud: the soft wet ground (the same field the wheels sink in) ------
	float mudv = texture(wetmap, uv).g * (1.0 - outback) * bp_mud_k;
	vec3 mudc = lin(mix(vec3(0.24, 0.19, 0.13), vec3(0.30, 0.24, 0.17), micro));
	float mudw = smoothstep(0.38, 0.75, mudv) * 0.85;
	col = mix(col, mudc, mudw);

	// --- cut and heaped ground, from real depth below the natural surface ---
	bool inside = abs(wpos.x) < sq && abs(wpos.z) < sq;
	float dug = inside ? L.r - wpos.y : 0.0;
	float heap = max(-dug, 0.0);
	if (heap > 0.03) {
		vec3 spoil = lin(mix(PAL(vec3(0.44, 0.42, 0.38), vec3(0.56, 0.26, 0.14)), PAL(vec3(0.56, 0.54, 0.50), vec3(0.66, 0.36, 0.20)), micro)) * (0.85 + 0.3 * fine);
		col = mix(col, spoil, smoothstep(0.03, 0.25, heap + (micro - 0.5) * 0.08));
	}
	if (dug > 0.03) {
		// Cut faces: what a drift or a pit wall actually shows. Brown dirt with
		// the odd stone in it, then the pay streak - rounded creek cobbles packed
		// in rusty gravel - then grey bedrock broken into blocks along joints.
		vec3 w3 = wpos;
		float m3 = vnoise3(w3 * 1.3);
		float f3 = vnoise3(w3 * 4.7 + 7.0);
		float clod = floor(vnoise3(w3 * 0.55 + 3.0) * 4.0 + 0.5) / 4.0;   // big posterised patches
		vec3 dirt = lin(mix(PAL(vec3(0.27, 0.20, 0.13), vec3(0.54, 0.25, 0.13)), PAL(vec3(0.40, 0.31, 0.21), vec3(0.66, 0.36, 0.20)), clod * 0.7 + m3 * 0.3));
		dirt *= 0.88 + 0.22 * f3;
		// a few roots and dark organic streaks near the top of the cut
		dirt = mix(dirt, lin(vec3(0.16, 0.12, 0.08)), smoothstep(0.62, 0.8, vnoise3(w3 * vec3(2.5, 0.6, 2.5))) * 0.5 * (1.0 - smoothstep(0.4, 1.2, dug)));
		// scattered stones in the dirt (fist to head sized)
		vec3 sd = stones3(w3 * 2.6);
		float in_d = step(sd.z, 0.32) * (1.0 - smoothstep(0.22, 0.30, sd.x));
		vec3 stone_d = lin(mix(vec3(0.36, 0.35, 0.33), vec3(0.55, 0.52, 0.47), fract(sd.z * 13.7))) * (0.8 + 0.35 * smoothstep(0.30, 0.0, sd.x));
		dirt = mix(dirt * (1.0 - 0.25 * step(sd.z, 0.32) * smoothstep(0.36, 0.27, sd.x)), stone_d, in_d);

		// pay gravel: dense rounded cobbles in rusty sandy matrix
		vec3 pg = stones3(w3 * 4.2 + 11.0);
		vec3 matrix = lin(mix(PAL(vec3(0.50, 0.37, 0.20), vec3(0.74, 0.52, 0.26)), PAL(vec3(0.60, 0.46, 0.27), vec3(0.82, 0.62, 0.32)), f3));
		matrix = mix(matrix, lin(vec3(0.66, 0.47, 0.22)), clamp(L.a * 0.25, 0.0, 0.4));
		float cob_t = fract(pg.z * 7.31);
		vec3 cob = lin(cob_t < 0.45 ? mix(vec3(0.42, 0.42, 0.41), vec3(0.58, 0.57, 0.54), fract(pg.z * 31.0))
			: (cob_t < 0.75 ? mix(vec3(0.48, 0.32, 0.20), vec3(0.62, 0.42, 0.26), fract(pg.z * 23.0))
			: mix(vec3(0.30, 0.31, 0.33), vec3(0.38, 0.40, 0.42), fract(pg.z * 19.0))));
		float in_p = step(pg.z, 0.78) * (1.0 - smoothstep(0.30, 0.40, pg.x));
		cob *= 0.75 + 0.4 * smoothstep(0.40, 0.0, pg.x);          // rounded: lit middle, shaded rim
		vec3 pay = mix(matrix * (1.0 - 0.3 * smoothstep(0.48, 0.36, pg.x) * step(pg.z, 0.78)), cob, in_p);

		// bedrock: blocky, jointed, each block its own grey
		vec3 bk = stones3(w3 * vec3(0.9, 1.4, 0.9) + 5.0);
		float band = 0.85 + 0.25 * vnoise(vec2(wpos.y * 3.0, dot(p, vec2(0.5))));
		vec3 bed = lin(mix(PAL(vec3(0.31, 0.31, 0.33), vec3(0.42, 0.30, 0.26)), PAL(vec3(0.47, 0.46, 0.45), vec3(0.56, 0.42, 0.35)), bk.z)) * band;
		bed *= 0.9 + 0.15 * f3;
		bed = mix(bed, lin(vec3(0.62, 0.58, 0.48)), smoothstep(0.85, 0.95, vnoise3(w3 * vec3(0.8, 6.0, 0.8))) * 0.4);   // pale quartz seams
		bed *= mix(0.35, 1.0, smoothstep(0.0, 0.07, bk.y));      // dark open joints between blocks

		vec3 cut = dirt;
		float jit = (m3 - 0.5) * 0.25;
		cut = mix(cut, pay, smoothstep(L.g - 0.08, L.g + 0.08, dug + jit));
		cut = mix(cut, bed, smoothstep(L.b - 0.08, L.b + 0.12, dug + jit));
		// shallow cuts and ruts in soft ground are churned black mud
		cut = mix(cut, mudc, clamp(mudw * 0.9 + 0.25 * (1.0 - outback), 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.6, dug)));
		col = mix(col, cut, smoothstep(0.03, 0.22, dug + (micro - 0.5) * 0.1));
	}

	// --- quartz veins: milky white seams in the bedrock, rust-stained, gold
	// in the rich shoots. In a cut into rock they show plain; on thin cover
	// over the knoll a little white float shows through the moss.
	float metal = 0.0;
	if (inside && bp_vein_n > 0.5) {
		vec3 vn = vein_at(wpos, L.r);
		if (vn.x > 0.0) {
			float in_rock = smoothstep(L.b - 0.08, L.b + 0.12, max(dug, 0.0));
			float float_show = 0.45 * (1.0 - smoothstep(0.3, 0.9, L.b)) * (1.0 - smoothstep(0.03, 0.15, abs(dug)));
			float show = max(in_rock, float_show);
			vec3 w3 = wpos;
			float sug = vnoise3(w3 * 7.0);
			float blk = floor(vnoise3(w3 * 1.6 + 2.0) * 3.0 + 0.5) / 3.0;
			vec3 qz = lin(mix(vec3(0.80, 0.80, 0.77), vec3(0.93, 0.92, 0.89), blk * 0.6 + sug * 0.4));
			qz = mix(qz, lin(vec3(0.62, 0.63, 0.64)), smoothstep(0.62, 0.8, vnoise3(w3 * 2.3 + 9.0)) * 0.6);     // grey glassy patches
			qz = mix(qz, lin(vec3(0.58, 0.33, 0.14)), clamp(smoothstep(0.55, 0.8, vnoise3(w3 * 1.9 + 4.0)) * 0.7 + smoothstep(0.7, 1.0, vn.z) * 0.5, 0.0, 0.85));   // iron stain
			float rich = clamp(vn.y / 40.0, 0.0, 1.0);
			vec3 fl = stones3(w3 * 11.0 + 3.0);
			float fleck = step(fl.z, 0.04 + 0.22 * rich) * (1.0 - smoothstep(0.10, 0.16, fl.x)) * in_rock;
			qz = mix(qz, lin(vec3(1.0, 0.80, 0.28)), fleck);
			qz *= mix(1.0, 0.55, smoothstep(0.82, 1.0, vn.z));     // dark selvage at the walls
			float va = vn.x * show;
			col = mix(col, qz, va);
			metal = fleck * va;
		}
	}

	// --- track and tyre marks (wear.gd, DESIGN_NOTES 150) ------------------------
	// Where machines have run the turf is torn off and the dirt packed: brown
	// and darker, the tread prints showing; a little wet in the low spots.
	float wear = texture(bp_wear, uv).r * up * (1.0 - smoothstep(0.03, 0.15, abs(dug)));
	if (wear > 0.01) {
		vec3 torn = lin(vec3(0.33, 0.26, 0.18)) * (0.82 + 0.3 * fine);
		col = mix(col, torn, smoothstep(0.02, 0.55, wear) * 0.9);
		col *= 1.0 - 0.18 * smoothstep(0.45, 1.0, wear);
	}

	// --- wetness ----------------------------------------------------------
	// Painted-on rain puddles belong to the undisturbed gravel and muskeg only:
	// a dug hole stays dry until real groundwater exists (DESIGN_NOTES 62).
	float undug = 1.0 - smoothstep(0.03, 0.15, abs(dug));
	float puddle = smoothstep(0.80, 0.92, fbm(p * 0.33 + 3.0)) * max(zone.r, zone.g * 0.7) * up * undug;
	puddle = max(puddle, smoothstep(0.72, 0.9, mudv + (fine - 0.5) * 0.2) * up);
	float wet = clamp((wetv + 0.25 * zone.g) * mix(0.5, 1.0, undug) + puddle + mudw * 0.75, 0.0, 1.0);
	col *= 1.0 - 0.18 * wet;

	// --- snow ----------------------------------------------------------------
	float clump = fbm(p * 0.21 + 41.0);
	float line = bp_snow_line + (meso - 0.5) * 240.0;
	float snow = smoothstep(line - 70.0, line + 70.0, wpos.y) * smoothstep(0.45 + 0.1 * clump, 0.72, up);
	snow = max(snow, bp_snow_cover * smoothstep(0.40, 0.66, up + (clump - 0.5) * 0.12));
	snow *= 1.0 - smoothstep(0.05, 0.25, abs(dug));                   // fresh workings stay dark
	float melted = texture(bp_melt, uv).r;
	snow *= 1.0 - smoothstep(0.35, 0.95, melted + (fine - 0.5) * 0.25);   // a ragged edge round the burn
	// thawed ground is dark and wet: soaked peat and moss, a darker ring at the melt line
	float thaw = smoothstep(0.3, 0.9, melted) * bp_snow_cover;
	col = mix(col, lin(vec3(0.16, 0.12, 0.08)) * (0.85 + 0.3 * fine), thaw * 0.92);
	col *= 1.0 - 0.3 * smoothstep(0.05, 0.5, melted) * (1.0 - smoothstep(0.5, 1.0, melted)) * bp_snow_cover;
	col = mix(col, bp_col_snow * (0.95 + 0.08 * fine), snow);
	wet *= 1.0 - snow;
	puddle *= 1.0 - snow;

	// rain: everything goes dark and shiny, low spots fill and mirror the lights
	float rw = bp_rain * (1.0 - snow);
	float pool = rw * smoothstep(0.66, 0.78, vnoise(p * 0.45) + 0.04 * rw) * smoothstep(0.93, 0.99, up);
	col *= mix(1.0, 0.58, rw);
	col = mix(col, col * 0.4, pool);
	ALBEDO = col;
	metal *= 1.0 - snow;
	float rough0 = mix(clamp(mix(0.97, 0.72, wet) - 0.45 * puddle - 0.15 * snow, 0.25, 1.0), 0.3, metal);
	ROUGHNESS = mix(mix(rough0, 0.32, rw * 0.8), 0.05, pool);
	SPECULAR = 0.08 + 0.10 * wet + 0.30 * puddle + 0.25 * rw + 0.4 * pool;
	METALLIC = metal;
}
