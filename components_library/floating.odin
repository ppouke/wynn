package components_library

import wynn ".."

FLOATING_COLOR :: wynn.vec4{0.16, 0.17, 0.21, 1}

// A floating window: a container parented to the screen, positioned absolutely
// at `pos` with size `size`, floating above other UI and never clipped to a
// flow parent. Children added under the returned handle lay out within it
// (by their own anchors, or set a layout on the returned handle).
//
// Static by design: there is no built-in drag or z-order raise. To make it
// draggable add the `Move` trait; to raise it on interaction call
// `wynn.bring_to_front`. (Created later than other screen children, it renders
// on top until something else is raised.)
floating :: proc(
	ctx: ^wynn.Context,
	pos: wynn.vec2,
	size: wynn.vec2,
	color := FLOATING_COLOR,
) -> wynn.Handle {
	h := wynn.new_child(ctx, ctx.screen)
	c := wynn.get_component(ctx, h)
	c.rect.pos = pos
	c.constraints.pref_size = size
	c.color = color
	return h
}
