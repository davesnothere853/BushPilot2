shader_type spatial;
render_mode cull_disabled;

// Trees, shrubs, ground plants and rocks. Vertex colour RGB is the part's own
// colour; alpha 1 marks leaves and needles, which the season tints and which
// sway in the wind. INSTANCE_CUSTOM.x is a per-plant random number.
#include "res://shaders/veg_common.gdshaderinc"
