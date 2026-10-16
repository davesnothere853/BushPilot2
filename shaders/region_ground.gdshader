shader_type spatial;
render_mode world_vertex_coords;

// The region's ground (DESIGN_NOTES 228): real photo-scanned surfaces at their
// true size so the land reads at its real scale - meadow grass and forest
// floor on the gentle ground, rock (projected three ways, so cliffs aren't
// smeared) on the steep, snow up high and where it lies flat, river gravel in
// the channels. The vertex colour is the land's colour map (fields, forest,
// meadow, rock) seen from afar; the scans add the detail up close and fade
// out with distance so no tiling shows from the air.
// UV.x: meadow/field (1) vs forest floor (0); UV.y: gravel bar.

uniform sampler2D grass_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_m = 3.0;      // metres a tile
uniform float forest_m = 4.0;
uniform float rock_m = 7.0;
uniform float snow_m = 6.0;
uniform float gravel_m = 3.0;
uniform float snow_line = 640.0;
uniform float season_snow = 0.0;  // 0 summer .. 1 deep winter: brings the snow line down
uniform float detail_far = 1800.0;
uniform bool use_detail = true;   // false where the scans aren't on disk

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 mask;

void vertex() {
	wpos = VERTEX;
	wnrm = NORMAL;
	mask = UV;
}

vec3 unpack(vec4 t) { return t.xyz * 2.0 - 1.0; }
vec3 safe_n(vec3 v, vec3 fb) { float l = length(v); return (l > 1e-4 && l == l) ? v / l : fb; }

void fragment() {
	vec3 n = safe_n(wnrm, vec3(0.0, 1.0, 0.0));
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = use_detail ? 1.0 - smoothstep(60.0, detail_far, dist) : 0.0;
	// two scales of every scan, the larger breaking up the repeat
	vec2 xz = wpos.xz;
	float slope = 1.0 - n.y;
	// bare rock: cliffs anywhere, but below the treeline the forest holds on
	// to all but the steepest ground (Dave's photo: forested to the treeline)
	float tl = smoothstep(520.0, 640.0, wpos.y);
	float w_rock = smoothstep(mix(0.42, 0.24, tl), mix(0.62, 0.42, tl), slope);
	float sl = snow_line - season_snow * 560.0;
	float w_snow = smoothstep(sl - 25.0, sl + 35.0, wpos.y + sin(wpos.x * 0.04) * 18.0) * (1.0 - smoothstep(0.35, 0.6, slope));
	float w_grav = mask.y * (1.0 - w_rock);
	float w_grass = mask.x;
	// flat materials
	vec4 g = texture(grass_c, xz / grass_m) * 0.6 + texture(grass_c, xz / (grass_m * 7.3)) * 0.4;
	vec4 f = texture(forest_c, xz / forest_m) * 0.6 + texture(forest_c, xz / (forest_m * 6.1)) * 0.4;
	vec4 gr = texture(gravel_c, xz / gravel_m);
	vec4 s = texture(snow_c, xz / snow_m);
	vec3 gn = unpack(texture(grass_n, xz / grass_m));
	vec3 fn = unpack(texture(forest_n, xz / forest_m));
	vec3 grn = unpack(texture(gravel_n, xz / gravel_m));
	vec3 sn = unpack(texture(snow_n, xz / snow_m));
	vec3 flat_c = mix(f.rgb, g.rgb, w_grass);
	vec3 flat_n = mix(fn, gn, w_grass);
	flat_c = mix(flat_c, gr.rgb, w_grav);
	flat_n = mix(flat_n, grn, w_grav);
	// rock: triplanar
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 rx = texture(rock_c, wpos.zy / rock_m).rgb;
	vec3 ry = texture(rock_c, wpos.xz / rock_m).rgb;
	vec3 rz = texture(rock_c, wpos.xy / rock_m).rgb;
	vec3 rx2 = texture(rock_c, wpos.zy / (rock_m * 5.7)).rgb;
	vec3 rz2 = texture(rock_c, wpos.xy / (rock_m * 5.7)).rgb;
	vec3 rc = (rx * 0.6 + rx2 * 0.4) * bw.x + ry * bw.y + (rz * 0.6 + rz2 * 0.4) * bw.z;
	vec3 nx = unpack(texture(rock_n, wpos.zy / rock_m));
	vec3 ny = unpack(texture(rock_n, wpos.xz / rock_m));
	vec3 nz = unpack(texture(rock_n, wpos.xy / rock_m));
	// whiteout blend of the three projections into a world normal
	vec3 rn = safe_n(vec3(nx.z, nx.y, nx.x) * bw.x * sign(n.x) + vec3(ny.x, ny.z, ny.y) * bw.y + vec3(nz.x, nz.y, nz.z) * bw.z * sign(n.z) + n, n);
	// the flat materials' normal into world space (tangent: +x, bitangent: +z)
	vec3 fwn = safe_n(vec3(flat_n.x, flat_n.z, -flat_n.y) * 0.8 + n, n);
	vec3 detail = mix(flat_c, rc, w_rock);
	vec3 dn = safe_n(mix(fwn, rn, w_rock), n);
	detail = mix(detail, s.rgb, w_snow);
	dn = safe_n(mix(dn, safe_n(vec3(sn.x, sn.z, -sn.y) * 0.5 + n, n), w_snow), n);
	// colour: the map's colour near and far, the scan's own colour and grain up close
	vec3 macro = pow(COLOR.rgb, vec3(2.2));      // the colour map is stored sRGB
	float lum = dot(detail, vec3(0.299, 0.587, 0.114));
	vec3 near_c = mix(macro * (lum / 0.32), detail, 0.55);
	ALBEDO = clamp(mix(mix(macro, vec3(0.92, 0.93, 0.96), w_snow), mix(near_c, detail, w_snow), near), vec3(0.0), vec3(0.95));
	vec3 nw = safe_n(mix(n, dn, near * 0.9 + 0.1), n);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = mix(0.95, 0.7, w_snow);
	SPECULAR = 0.3;
}
