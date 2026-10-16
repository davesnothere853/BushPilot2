shader_type spatial;
render_mode cull_disabled;

// Needle and leaf cards on trees: the same as veg.gdshader, plus a cut-out
// picture (veg_textures.gd) for the fine detail.
#define CARDS
#include "res://shaders/veg_common.gdshaderinc"
