// Tyre deformation (DESIGN_NOTES 209): the tyre flattens where it sits on
// the ground and its sidewalls bulge out there - more under load. Done in
// world space against the truck's "down", so the flat spot stays at the
// bottom while the wheel turns. The rim isn't touched (only the rubber,
// outside rim_r, gives).
shader_type spatial;
render_mode cull_back;

uniform float radius = 0.42;      // the tyre's outside radius
uniform float rim_r = 0.19;       // the rim (doesn't squash)
instance uniform float squash = 0.02;            // metres pressed flat at the bottom
instance uniform vec3 down_dir = vec3(0.0, -1.0, 0.0);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	float rv = length(VERTEX.yz);
	if (rv > rim_r + 0.015 && squash > 0.0005) {
		vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 c = MODEL_MATRIX[3].xyz;
		vec3 axle = normalize(MODEL_MATRIX[0].xyz);
		vec3 dn = normalize(down_dir);
		float d = dot(wpos - c, dn);
		float lim = radius - squash;
		// how much of the rubber's height (rim to tread) this vertex is: the
		// tread squashes, the sidewall nearer the rim less
		float rub = clamp((rv - rim_r) / max(radius - rim_r, 0.01), 0.0, 1.0);
		float near = smoothstep(lim - 0.10, lim, d);              // close to the contact patch
		if (d > lim) {
			wpos -= dn * (d - lim);                               // flat on the ground
		}
		// which way this bit of sidewall bulges: smooth across the tread's
		// middle (a hard sign() tore the tread apart there as the wheel rolled
		// - black slivers flicking out round the tyre, "smoke")
		float side = clamp(dot(wpos - c, axle) / 0.06, -1.0, 1.0);
		wpos += axle * side * near * squash * 0.9 * rub;          // the sidewall bulges out
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
	}
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
