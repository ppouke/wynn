package wynn_test

import "core:testing"
import wynn ".."
import cl "../components_library"

// The immediate-mode menu: a toolbar title button plus, when open, a floating
// dropdown. `open` is caller-owned (holds the open menu's id, or 0). `menu`
// returns the index of the item clicked this frame, or -1.
//
// Toolbar geometry: full-width Row, padding {4,4,4,4}. The "File" title is the
// first item -> {4,4 .. 60,32}, center {32,18}. The dropdown opens just below
// at {4,32}; column items (padding 2, gap {0,2}, item {150,26}) put item 1
// ("Open") at {6,62 .. 156,88}, center {81,75}.

Menu_State :: struct {
	open:   wynn.ID,
	result: int,
}

build_menu :: proc(ctx: ^wynn.Context, st: ^Menu_State) {
	cl.begin_toolbar(ctx)
	st.result = cl.menu(ctx, &st.open, "menu.file", "File", {"New", "Open", "Quit"})
	cl.end_toolbar(ctx)
}

@(test)
test_menu_closed_emits_only_title :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Menu_State

	frame(ctx, build_menu, &st)

	testing.expect_value(t, st.open, wynn.ID(0))
	testing.expect_value(t, overlay_count(ctx), 0) // no dropdown
}

@(test)
test_menu_opens_on_title_click :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Menu_State

	frame(ctx, build_menu, &st)        // geometry
	click(ctx, {32, 18}, build_menu, &st) // click the title

	testing.expect_value(t, st.open, wynn.get_id("menu.file"))
	testing.expect(t, overlay_count(ctx) > 0) // dropdown now emitted
}

@(test)
test_menu_item_click_returns_index :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Menu_State

	frame(ctx, build_menu, &st)            // geometry
	click(ctx, {32, 18}, build_menu, &st)  // open the menu
	frame(ctx, build_menu, &st)            // settle: dropdown items enter prev_nodes
	click(ctx, {81, 75}, build_menu, &st)  // click item 1 ("Open")

	testing.expect_value(t, st.result, 1)
	testing.expect_value(t, st.open, wynn.ID(0)) // selection closes the menu
}

@(test)
test_menu_closes_on_outside_press :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Menu_State

	frame(ctx, build_menu, &st)
	click(ctx, {32, 18}, build_menu, &st) // open
	testing.expect_value(t, st.open, wynn.get_id("menu.file"))
	frame(ctx, build_menu, &st) // settle

	// a press anywhere outside the title/items closes the menu
	press_frame(ctx, {400, 400}, build_menu, &st)
	testing.expect_value(t, st.open, wynn.ID(0))
}

@(test)
test_floating_window :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	pos := wynn.vec2{120, 80}

	wynn.begin_frame(ctx, SCREEN)
	winidx := len(ctx.nodes)
	cl.begin_floating(ctx, "win", &pos, {260, 180}, layout = wynn.Layout{})
	childidx := len(ctx.nodes)
	wynn.label(ctx, "hi", size = {50, 20})
	ctx.nodes[childidx].rect.pos = {10, 10}
	cl.end_floating(ctx)
	wynn.end_frame(ctx)

	w := ctx.nodes[winidx]
	testing.expect_value(t, w.parent, 0) // parented to the screen root
	testing.expect_value(t, w.rect.pos, wynn.vec2{120, 80})
	testing.expect_value(t, w.constraints.pref_size, wynn.vec2{260, 180})
	testing.expect_value(t, w.global_rect.pos, wynn.vec2{120, 80})

	// content is positioned relative to the window's absolute origin
	testing.expect_value(t, ctx.nodes[childidx].global_rect.pos, wynn.vec2{130, 90})
}
