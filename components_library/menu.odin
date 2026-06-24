package components_library

import wynn ".."

// ----------------------------------------------------------------------------
// Dropdown menus
//
// A `menu` adds a clickable title to a toolbar and builds a (initially hidden)
// dropdown column of item buttons parented to the screen, so it floats above
// everything and is never clipped to the toolbar.
//
// Two layers of API:
//   - mechanism: menu_show / menu_hide / menu_is_open / menu_hovered / menu_items
//   - policy:    menu_bar_update implements the default hover-to-open behavior.
// Use the driver for the common case, or the ops directly for custom behavior.
// ----------------------------------------------------------------------------

MENU_MAX_ITEMS :: 16

MENU_COLOR :: wynn.vec4{0.18, 0.18, 0.22, 1}

Menu :: struct {
	title:    wynn.Handle, // the toolbar button
	dropdown: wynn.Handle, // the hidden column of items (child of the screen)
	items:    [MENU_MAX_ITEMS]wynn.Handle,
	count:    int,
}

// Adds a titled menu to `bar` with a dropdown of `labels`. The dropdown starts
// hidden. Up to MENU_MAX_ITEMS items are used.
menu :: proc(
	ctx: ^wynn.Context,
	bar: wynn.Handle,
	title: string,
	labels: []string,
	title_w: f32 = 56,
	title_h: f32 = 28,
	item_w: f32 = 150,
	item_h: f32 = 26,
) -> Menu {
	m: Menu
	m.title = wynn.button(ctx, bar, title, size = {title_w, title_h})

	dd := wynn.column(ctx, ctx.screen, gap = 2, padding = {2, 2, 2, 2})
	dc := wynn.get_component(ctx, dd)
	dc.visible = false
	dc.color = MENU_COLOR
	m.dropdown = dd

	n := min(len(labels), MENU_MAX_ITEMS)
	for i in 0 ..< n {
		m.items[i] = wynn.button(ctx, dd, labels[i], size = {item_w, item_h})
	}
	m.count = n

	// Size the dropdown to fit its items (matches the Column gap/padding above).
	dc.constraints.pref_size = {item_w + 4, f32(n) * item_h + f32(max(0, n - 1)) * 2 + 4}
	return m
}

// The item handles, as a slice (length == number of items).
menu_items :: proc(m: ^Menu) -> []wynn.Handle {
	return m.items[:m.count]
}

menu_is_open :: proc(ctx: ^wynn.Context, m: ^Menu) -> bool {
	return wynn.get_component(ctx, m.dropdown).visible
}

// Opens the dropdown: positions it directly under the title and raises it
// above other content. (Reads the title's resolved rect from the last frame.)
menu_show :: proc(ctx: ^wynn.Context, m: ^Menu) {
	tr := wynn.get_component(ctx, m.title).global_rect
	dd := wynn.get_component(ctx, m.dropdown)
	dd.rect.pos = {tr.pos.x, tr.pos.y + tr.size.y}
	dd.visible = true
	wynn.bring_to_front(ctx, m.dropdown)
}

menu_hide :: proc(ctx: ^wynn.Context, m: ^Menu) {
	wynn.get_component(ctx, m.dropdown).visible = false
}

// Whether the cursor is over the title or anywhere within the dropdown.
menu_hovered :: proc(ctx: ^wynn.Context, m: ^Menu) -> bool {
	h := ctx.hovered
	return wynn.is_descendant(ctx, h, m.title) || wynn.is_descendant(ctx, h, m.dropdown)
}

// Default hover-to-open menu-bar policy. `open` (caller-owned) is the index of
// the open menu, or -1. Opens the hovered title's menu, keeps it open while the
// cursor stays within it, switches on hover, and closes on selection. Returns
// the item handle clicked this frame, or NULL_HANDLE.
//
// Call once per frame between process_input and process_ui (menu_show moves the
// dropdown, which the following layout solve must pick up).
menu_bar_update :: proc(ctx: ^wynn.Context, menus: []Menu, open: ^int) -> wynn.Handle {
	desired := -1
	for m, i in menus {
		if wynn.is_hovered(ctx, m.title) {
			desired = i
		}
	}
	// Stay open while hovering the current menu's title or its dropdown.
	if open^ >= 0 && desired == -1 && menu_hovered(ctx, &menus[open^]) {
		desired = open^
	}
	if desired != open^ {
		if open^ >= 0 {
			menu_hide(ctx, &menus[open^])
		}
		open^ = desired
		if open^ >= 0 {
			menu_show(ctx, &menus[open^])
		}
	}
	// Selecting an item reports it and closes the menu.
	if open^ >= 0 {
		for it in menu_items(&menus[open^]) {
			if wynn.was_clicked(ctx, it) {
				menu_hide(ctx, &menus[open^])
				open^ = -1
				return it
			}
		}
	}
	return wynn.NULL_HANDLE
}
