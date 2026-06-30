package components_library

import wynn ".."

TOOLBAR_COLOR :: wynn.vec4{0.12, 0.13, 0.16, 1}

// A full-width toolbar pinned to the top, laid out as a Row. Emit `menu`s (or
// other widgets) between begin_toolbar and end_toolbar.
begin_toolbar :: proc(
	ctx: ^wynn.Context,
	height: f32 = 30,
	gap: f32 = 2,
	padding := wynn.Sides{4, 4, 4, 4},
	color := TOOLBAR_COLOR,
) {
	wynn.begin_container(
		ctx,
		wynn.Layout{kind = .Row, gap = {gap, 0}, padding = padding},
		color,
		wynn.Constraints{anchors = {.Left, .Top, .Right}, pref_size = {0, height}},
	)
}

end_toolbar :: proc(ctx: ^wynn.Context) {
	wynn.pop_container(ctx)
}
