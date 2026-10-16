// Shared body of veg.gdshader (plain plant parts) and veg_cards.gdshader
// (needle and leaf cards with a cut-out picture).

// Trees, shrubs, ground plants and rocks. Vertex colour RGB is the part's own
// colour; alpha 1 marks leaves and needles, which the season tints and which
// sway in the wind. INSTANCE_CUSTOM.x is a per-plant random number.

uniform vec3 leaf_tint : source_color = vec3(1.0);
uniform vec3 leaf_alt : source_color = vec3(0.85, 0.58, 0.10);   // autumn colour
uniform float alt_amount = 0.0;
uniform float snow = 0.0;
uniform float sway = 1.0;
uniform vec2 wind = vec2(1.0, 0.3);
uniform float wind_strength = 0.4;
uniform vec3 cam_pos = vec3(0.0);
uniform vec2 fade_in = vec2(-2.0, -1.0);    // dissolve in between these distances
uniform vec2 fade_out = vec2(1.0e6, 2.0e6);  // and out between these
#ifdef CARDS
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
#endif

varying float leaf;
varying vec3 base_col;
varying float rnd;
varying float up_facing;
varying vec3 wpos;
varying float charred;    // INSTANCE_CUSTOM.y: a tree brought down by fire

void vertex() {
	leaf = COLOR.a;
	base_col = pow(COLOR.rgb, vec3(2.2));   // vertex colours are written in sRGB
	rnd = INSTANCE_CUSTOM.x;
	charred = INSTANCE_CUSTOM.y;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = origin.x * 0.13 + origin.z * 0.17;
	float h = clamp(VERTEX.y, 0.0, 1.2);
	float gust = 0.6 + 0.4 * sin(TIME * 0.7 + ph) * sin(TIME * 0.31 + ph * 0.5);
	float bend = h * h * sway * wind_strength * gust * 0.03;
	vec3 wdir = (inverse(MODEL_MATRIX) * vec4(wind.x, 0.0, wind.y, 0.0)).xyz;
	float l = length(wdir.xz);
	if (l > 0.0001) {
		wdir.xz /= l;
	}
	VERTEX.xz += wdir.xz * bend * (1.0 + 0.25 * sin(TIME * 1.9 + ph));
	VERTEX.xz += leaf * h * 0.006 * wind_strength * sin(TIME * 5.0 + ph * 3.0 + VERTEX.x * 17.0) * vec2(1.0, 0.7);
	up_facing = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Dissolve at the edges of the drawn range (a stable pattern, so no shimmer).
	float d = length(wpos - cam_pos);
	float vis = smoothstep(fade_in.x, fade_in.y, d) * (1.0 - smoothstep(fade_out.x, fade_out.y, d));
	if (vis < 0.999) {
		vec2 cell = floor(FRAGCOORD.xy);
		float dither = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
		if (dither >= vis) {
			discard;
		}
	}
	vec3 c = base_col;
#ifdef CARDS
	// Needle and leaf cards: the picture's cut-out decides what is solid. The
	// edge is sharpened so distant (smaller, blurrier) cards stay full instead
	// of thinning away.
	vec4 t = texture(tex, UV);
	float a = (t.a - 0.5) / max(fwidth(t.a), 0.0001) + 0.5;
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	c *= t.rgb * 2.1;
#endif
	if (leaf > 0.5) {
		// Thin leaves and blades: light both sides the same, like foliage.
		NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
		// Each plant a little different: some greener, some yellower, some greyer.
		vec3 warm = c * vec3(1.10, 1.04, 0.86);
		vec3 cool = c * vec3(0.92, 0.98, 1.04);
		c = mix(cool, warm, rnd) * (0.86 + 0.28 * fract(rnd * 7.31));
		c *= leaf_tint;
		c = mix(c, leaf_alt * (0.75 + 0.5 * rnd), alt_amount * step(0.12, rnd));
		c = mix(c, vec3(0.84, 0.87, 0.92), snow * smoothstep(0.15, 0.75, up_facing));
		BACKLIGHT = c * 0.4;
	} else {
		c *= 0.9 + 0.2 * rnd;
		c = mix(c, vec3(0.82, 0.85, 0.90), snow * 0.8 * smoothstep(0.55, 0.9, up_facing));
	}
	if (charred > 0.5) {
		c = vec3(0.035, 0.03, 0.026) * (0.8 + 0.5 * rnd);      // burnt black, no snow on it yet
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
