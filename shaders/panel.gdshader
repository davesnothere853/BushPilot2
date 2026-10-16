shader_type spatial;
render_mode cull_back;

// The instrument panel's painted surface, with round holes where the 3D
// instruments sit (their cases are set back into the panel behind the holes).

uniform sampler2D panel_tex : source_color, filter_linear;
uniform int hole_count = 0;
uniform vec4 holes[40];     // centre u, centre v, radius in u, radius in v
uniform float glow = 0.3;

void fragment() {
	for (int i = 0; i < hole_count; i++) {
		vec2 d = (UV - holes[i].xy) / holes[i].zw;
		if (dot(d, d) < 1.0) {
			discard;
		}
	}
	vec3 c = texture(panel_tex, UV).rgb;
	ALBEDO = c;
	EMISSION = c * glow;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
}
