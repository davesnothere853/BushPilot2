shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Far trees: one upright card per tree that turns to face you, carrying a
// picture of that kind of tree taken at load time (vegetation.gd). Shaded as
// a rounded crown so it sits with the near trees, and dissolved in where the
// near trees dissolve out.

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 cam_pos = vec3(0.0);
uniform vec2 fade_in = vec2(-2.0, -1.0);
uniform vec2 fade_out = vec2(1.0e6, 2.0e6);
uniform float snow = 0.0;

varying vec3 wpos;
varying vec3 v_right;
varying vec3 v_face;
varying float rnd;

void vertex() {
	rnd = INSTANCE_CUSTOM.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	// VERTEX arrives already in world space (world_vertex_coords); undo that to
	// get the card's own corner, then stand it up facing the camera.
	vec3 local = (inverse(MODEL_MATRIX) * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float flip = rnd > 0.5 ? 1.0 : -1.0;     // mirror half of them for variety
	VERTEX = origin + right * local.x * sx * flip + vec3(0.0, local.y * sy, 0.0);
	NORMAL = to_cam;
	wpos = VERTEX;
	v_right = right * flip;
	v_face = to_cam;
}

void fragment() {
	float d = length(wpos - cam_pos);
	float vis = smoothstep(fade_in.x, fade_in.y, d) * (1.0 - smoothstep(fade_out.x, fade_out.y, d));
	if (vis < 0.999) {
		vec2 cell = floor(FRAGCOORD.xy);
		float dither = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
		if (dither >= vis) {
			discard;
		}
	}
	vec4 t = texture(tex, UV);
	float a = (t.a - 0.5) / max(fwidth(t.a), 0.0001) + 0.5;
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// A rounded crown: the sides turn away, the top faces up.
	float u = UV.x * 2.0 - 1.0;
	vec3 n = normalize(v_right * u * 0.9 + v_face * 0.7 + vec3(0.0, 0.35 + 0.4 * (1.0 - UV.y), 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 c = t.rgb * (0.9 + 0.2 * rnd);
	c = mix(c, vec3(0.84, 0.87, 0.92), snow * 0.45 * smoothstep(0.2, 0.8, n.y));
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = c * 0.3;
}
