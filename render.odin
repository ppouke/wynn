package wynn

import "core:mem"

// ----------------------------------------------------------------------------
// Render-data emission
//
// The node arena is built in creation order, which is painter order (a parent
// is pushed before its children, siblings in call order), so we can emit it as
// a flat slice by index — index 0 (screen root) is skipped. Pressable nodes are
// emitted slightly darkened while held (active), giving free press feedback.
//
// The returned slice is allocated with `allocator`; the caller frees it.
// ----------------------------------------------------------------------------

// RGB multiplier applied to a pressable node's color while it is held.
PRESS_DARKEN :: 0.82

render :: proc(ctx: ^Context, allocator: mem.Allocator) -> []Render_Data {
	out := make([dynamic]Render_Data, allocator)

	max_layer := 0
	for n in ctx.nodes {
		if n.layer > max_layer {
			max_layer = n.layer
		}
	}

	// Emit layer by layer (low first) so overlays draw on top; array order is
	// painter order within a layer.
	for layer in 0 ..= max_layer {
		for i in 1 ..< len(ctx.nodes) {
			n := ctx.nodes[i]
			if n.layer != layer {
				continue
			}
			color := n.color
			if .Press in n.traits && n.id != 0 && n.id == ctx.active {
				color *= vec4{PRESS_DARKEN, PRESS_DARKEN, PRESS_DARKEN, 1}
			}
			append(
				&out,
				Render_Data {
					traits = n.traits,
					rect = n.global_rect,
					color = color,
					text = n.text,
					text_size = n.text_size,
					value = n.value,
				},
			)
		}
	}

	return out[:]
}
