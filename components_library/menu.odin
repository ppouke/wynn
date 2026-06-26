package components_library

import wynn ".."

MENU_COLOR :: wynn.vec4{0.18, 0.18, 0.22, 1}
MENU_TITLE_COLOR :: wynn.vec4{0.18, 0.18, 0.22, 1}

@(private = "file")
item_id :: proc(base: wynn.ID, i: int) -> wynn.ID {
	return base ~ wynn.ID(u64(i + 1) * 0x9e3779b97f4a7c15)
}

// A toolbar dropdown menu (click-to-toggle). `open` is app-owned and holds the
// id of the currently open menu (or 0), so only one menu in the bar is open at
// a time. Renders the title in the current toolbar and, when open, a floating
// dropdown of `items`. Returns the index of the item clicked this frame, or -1.
//
// Behavior: click the title to open/close; click an item to select and close;
// press anywhere outside the open menu to close.
menu :: proc(
	ctx: ^wynn.Context,
	open: ^wynn.ID,
	id: string,
	title: string,
	items: []string,
	title_w: f32 = 56,
	title_h: f32 = 28,
	item_w: f32 = 150,
	item_h: f32 = 26,
) -> int {
	wid := wynn.get_id(id)

	if wynn.button_id(ctx, wid, title, {title_w, title_h}, MENU_TITLE_COLOR) {
		open^ = wid if open^ != wid else 0
	}

	result := -1
	if open^ == wid {
		// Position the dropdown under the title using last frame's title rect.
		tr, ok := wynn.prev_rect(ctx, wid)
		pos := wynn.vec2{0, title_h}
		if ok {
			pos = {tr.pos.x, tr.pos.y + tr.size.y}
		}
		n := len(items)
		ddh := f32(n) * item_h + f32(max(0, n - 1)) * 2 + 4

		wynn.begin_overlay(
			ctx,
			pos,
			{item_w + 4, ddh},
			MENU_COLOR,
			wynn.Layout{kind = .Column, gap = {0, 2}, padding = {2, 2, 2, 2}},
		)
		hot_inside := ctx.hot == wid
		for label, i in items {
			iid := item_id(wid, i)
			if wynn.button_id(ctx, iid, label, {item_w, item_h}) {
				result = i
				open^ = 0
			}
			if ctx.hot == iid {
				hot_inside = true
			}
		}
		wynn.end_overlay(ctx)

		// Close when a press lands outside this menu's title or items.
		if open^ == wid && .Left in ctx.input.buttons_pressed && !hot_inside {
			open^ = 0
		}
	}
	return result
}
