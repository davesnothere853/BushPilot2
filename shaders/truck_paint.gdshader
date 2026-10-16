// Truck paint (DESIGN_NOTES 206): the two-tone bands are worked out per
// PIXEL from the panel's height on the truck, not baked into triangles - so
// a colour edge is razor sharp wherever it falls (no zig-zags where a lip or
// a slanted arch crosses a paint line) and the panels need no extra edges cut
// in for the paint. The mesh's own coordinates ARE the truck's (every part is
// built in body space), so a door or a panel that swings or breaks off keeps
// its paint exactly where it was.
//
// Vertex colour alpha: 0 = "banded" (outer skin: the shader picks the colour
// by height), 1 = a fixed colour (insides, ends, undercoat) - used as is.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 paint_a : source_color = vec4(0.10, 0.20, 0.55, 1.0);   // main colour
uniform vec4 paint_b : source_color = vec4(0.92, 0.92, 0.90, 1.0);   // the band
uniform bool two_tone = true;
uniform float tone_lo = 0.74;
uniform float tone_hi = 1.096;
uniform float dust = 0.28;              // brown kicked up toward the bottom
uniform float dust_top = 0.80;          // the height the dust fades out at
uniform float y_off = 0.0;              // a part built in its own frame: its origin's height on the machine
uniform vec4 dust_col : source_color = vec4(0.42, 0.37, 0.30, 1.0);
uniform float rough = 0.30;
uniform sampler2D ripple : hint_normal;  // faint ripple in the reflections
uniform float ripple_k = 0.12;

// cut-outs (the plane's fabric skin behind its windows and door openings):
// pixels of this mesh inside any of these body-space boxes aren't drawn
uniform int cut_n = 0;
uniform vec3 cut_min[6];
uniform vec3 cut_max[6];

varying vec3 bpos;
varying vec3 bnrm;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	bpos = VERTEX;
	bnrm = NORMAL;
}

void fragment() {
	for (int i = 0; i < cut_n; i++) {
		if (all(greaterThan(bpos, cut_min[i])) && all(lessThan(bpos, cut_max[i]))) {
			discard;
		}
	}
	vec3 col;
	if (COLOR.a < 0.5) {
		bool band = two_tone && bpos.y > tone_lo && bpos.y < tone_hi;
		col = band ? paint_b.rgb : paint_a.rgb;
	} else {
		col = to_linear(COLOR.rgb);
	}
	float d = clamp((dust_top - (bpos.y + y_off)) / 0.35, 0.0, 1.0) * dust;
	col = mix(col, dust_col.rgb, d);
	ALBEDO = col;
	ROUGHNESS = rough + d * 0.4;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = 1.0 - d;
	CLEARCOAT_ROUGHNESS = 0.10;
	// triplanar ripple in the body's own space
	vec3 an = abs(normalize(bnrm));
	vec2 uv = an.x > an.y && an.x > an.z ? bpos.zy : (an.y > an.z ? bpos.xz : bpos.xy);
	NORMAL_MAP = texture(ripple, uv * 1.6).rgb;
	NORMAL_MAP_DEPTH = ripple_k;
}
