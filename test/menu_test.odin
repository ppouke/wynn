package wynn_test

import "core:testing"
import wynn ".."
import cl "../components_library"

@(test)
test_bring_to_front :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	a := wynn.new_child(ctx, ctx.screen)
	b := wynn.new_child(ctx, ctx.screen)
	c := wynn.new_child(ctx, ctx.screen)

	// initial order a -> b -> c
	testing.expect_value(t, wynn.get_component(ctx, ctx.screen).first_child, a)
	testing.expect_value(t, wynn.get_component(ctx, ctx.screen).last_child, c)

	wynn.bring_to_front(ctx, a)
	// now b -> c -> a
	testing.expect_value(t, wynn.get_component(ctx, ctx.screen).first_child, b)
	testing.expect_value(t, wynn.get_component(ctx, ctx.screen).last_child, a)
	testing.expect_value(t, wynn.get_component(ctx, a).prev_sibling, c)
}

@(test)
test_is_descendant :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	p := wynn.new_child(ctx, ctx.screen)
	c := wynn.new_child(ctx, p)
	g := wynn.new_child(ctx, c)

	testing.expect(t, wynn.is_descendant(ctx, g, p)) // grandchild under p
	testing.expect(t, wynn.is_descendant(ctx, g, c))
	testing.expect(t, wynn.is_descendant(ctx, p, p)) // self
	testing.expect(t, !wynn.is_descendant(ctx, c, g)) // ancestor is not descendant
}

@(test)
test_menu_construction :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	tb := cl.toolbar(ctx, ctx.screen)
	m := cl.menu(ctx, tb, "File", {"New", "Open", "Quit"})

	testing.expect_value(t, wynn.get_component(ctx, m.title).parent, tb)
	testing.expect_value(t, wynn.get_component(ctx, m.dropdown).parent, ctx.screen)
	testing.expect_value(t, m.count, 3)
	testing.expect(t, !cl.menu_is_open(ctx, &m)) // hidden initially

	for it in cl.menu_items(&m) {
		testing.expect_value(t, wynn.get_component(ctx, it).parent, m.dropdown)
	}
}

@(test)
test_menu_show_positions_and_raises :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	tb := cl.toolbar(ctx, ctx.screen)
	m := cl.menu(ctx, tb, "File", {"New", "Open"})
	wynn.process_ui(ctx) // resolve the title's rect

	cl.menu_show(ctx, &m)
	testing.expect(t, cl.menu_is_open(ctx, &m))

	tr := wynn.get_component(ctx, m.title).global_rect
	dr := wynn.get_component(ctx, m.dropdown).rect.pos
	testing.expect_value(t, dr, wynn.vec2{tr.pos.x, tr.pos.y + tr.size.y}) // just below title
	// raised above siblings
	testing.expect_value(t, wynn.get_component(ctx, ctx.screen).last_child, m.dropdown)

	cl.menu_hide(ctx, &m)
	testing.expect(t, !cl.menu_is_open(ctx, &m))
}

@(test)
test_menu_item_click_and_hover :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	tb := cl.toolbar(ctx, ctx.screen)
	m := cl.menu(ctx, tb, "File", {"New", "Open", "Quit"})
	wynn.process_ui(ctx)
	cl.menu_show(ctx, &m)
	wynn.process_ui(ctx) // arrange the now-visible dropdown items

	items := cl.menu_items(&m)
	r := wynn.get_component(ctx, items[1]).global_rect
	center := r.pos + r.size * 0.5

	wynn.input_mouse_move(ctx, center)
	wynn.process_input(ctx)
	testing.expect(t, cl.menu_hovered(ctx, &m))

	click_at(ctx, center)
	testing.expect(t, wynn.was_clicked(ctx, items[1]))
}

// Drives the hover-to-open policy: open, switch, close, and select.
@(test)
test_menu_bar_update :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	tb := cl.toolbar(ctx, ctx.screen)
	menus := [2]cl.Menu {
		cl.menu(ctx, tb, "File", {"New", "Open"}),
		cl.menu(ctx, tb, "Edit", {"Undo"}),
	}
	open := -1
	wynn.process_ui(ctx)

	// One frame of the real loop order: process_input -> menu_bar_update ->
	// process_ui (so a freshly-opened dropdown is positioned for next frame).
	step :: proc(ctx: ^wynn.Context, menus: []cl.Menu, open: ^int, p: wynn.vec2) -> wynn.Handle {
		wynn.input_mouse_move(ctx, p)
		wynn.process_input(ctx)
		sel := cl.menu_bar_update(ctx, menus, open)
		wynn.process_ui(ctx)
		return sel
	}

	// title rects: File at {4,4,56,28}, Edit at {62,4,56,28}
	file_c := wynn.vec2{32, 18}
	edit_c := wynn.vec2{90, 18}

	// hover File -> opens menu 0
	step(ctx, menus[:], &open, file_c)
	testing.expect_value(t, open, 0)
	testing.expect(t, cl.menu_is_open(ctx, &menus[0]))

	// hover Edit -> switches to menu 1
	step(ctx, menus[:], &open, edit_c)
	testing.expect_value(t, open, 1)
	testing.expect(t, !cl.menu_is_open(ctx, &menus[0]))
	testing.expect(t, cl.menu_is_open(ctx, &menus[1]))

	// hover empty space -> closes
	step(ctx, menus[:], &open, {400, 300})
	testing.expect_value(t, open, -1)
	testing.expect(t, !cl.menu_is_open(ctx, &menus[1]))

	// reopen File (dropdown positioned + items arranged by step's process_ui)
	step(ctx, menus[:], &open, file_c)
	item0 := cl.menu_items(&menus[0])[0]
	ir := wynn.get_component(ctx, item0).global_rect
	center := ir.pos + ir.size * 0.5

	wynn.input_mouse_move(ctx, center)
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)
	cl.menu_bar_update(ctx, menus[:], &open) // press: still open, no click yet

	wynn.input_mouse_button_up(ctx, .Left)
	wynn.process_input(ctx)
	sel := cl.menu_bar_update(ctx, menus[:], &open) // release: click registered

	testing.expect_value(t, sel, item0)
	testing.expect_value(t, open, -1)
}
