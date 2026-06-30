package components_library

import wynn ".."

FLOATING_COLOR :: wynn.vec4{0.16, 0.17, 0.21, 1}

// A floating window on the overlay layer at app-owned `pos` (absolute). Emit
// children between begin_floating and end_floating; `layout` arranges them
// (Column by default). Dragging the window body updates `pos` (the Move trait
// drag is resolved here against the app-owned pointer).
begin_floating :: proc(
	ctx: ^wynn.Context,
	id: string,
	pos: ^wynn.vec2,
	size: wynn.vec2,
	color := FLOATING_COLOR,
	layout := wynn.Layout{kind = .Column},
) {
	wid := wynn.get_id(id)
	idx := wynn.begin_overlay(ctx, pos^, size, color, layout)
	ctx.nodes[idx].id = wid
	ctx.nodes[idx].traits += {.Move}

	// Drag the window body (active when the body, not a child, was pressed).
	if wynn.is_active(ctx, wid) && .Left in ctx.input.buttons_down {
		pos^ += ctx.input.mouse_delta
		ctx.nodes[idx].rect.pos = pos^
	}
}

end_floating :: proc(ctx: ^wynn.Context) {
	wynn.end_overlay(ctx)
}
