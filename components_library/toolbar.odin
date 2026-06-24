package components_library

import wynn ".."

TOOLBAR_COLOR :: wynn.vec4{0.12, 0.13, 0.16, 1}

// A full-width toolbar pinned to the top of `parent`, laid out as a Row.
// Meant to hold `menu` titles (see menu.odin).
toolbar :: proc(
	ctx: ^wynn.Context,
	parent: wynn.Handle,
	height: f32 = 30,
	gap: f32 = 2,
	padding := wynn.Sides{4, 4, 4, 4},
	color := TOOLBAR_COLOR,
) -> wynn.Handle {
	h := wynn.new_child(ctx, parent)
	c := wynn.get_component(ctx, h)
	c.layout = wynn.Layout {
		kind    = .Row,
		gap     = {gap, 0},
		padding = padding,
	}
	c.color = color
	c.constraints.anchors = {.Left, .Top, .Right} // stretch full width, fixed height
	c.constraints.pref_size = {0, height}
	return h
}
