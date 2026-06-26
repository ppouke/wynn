package wynn_test

import "core:testing"
import wynn ".."

@(test)
test_label :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	idx := len(ctx.nodes)
	wynn.label(ctx, "Hello", text_size = 18)
	wynn.end_frame(ctx)

	n := ctx.nodes[idx]
	testing.expect(t, .Text in n.traits)
	testing.expect_value(t, n.text, "Hello")
	testing.expect_value(t, n.text_size, f32(18))
	testing.expect_value(t, n.id, wynn.ID(0)) // non-interactive
}

@(test)
test_label_emitted_with_text :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	wynn.label(ctx, "Hi", text_size = 12)
	wynn.end_frame(ctx)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 1)
	testing.expect_value(t, data[0].text, "Hi")
	testing.expect_value(t, data[0].text_size, f32(12))
	testing.expect(t, .Text in data[0].traits)
}

@(test)
test_button_traits_and_size :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	idx := len(ctx.nodes)
	wynn.button(ctx, "ok", "OK", {120, 40})
	wynn.end_frame(ctx)

	n := ctx.nodes[idx]
	testing.expect(t, .Press in n.traits)
	testing.expect(t, .Text in n.traits)
	testing.expect_value(t, n.text, "OK")
	testing.expect_value(t, n.constraints.pref_size, wynn.vec2{120, 40})
}

@(test)
test_button_click :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Box_State // button "box" at {100,100 .. 200,200}, center {150,150}

	frame(ctx, build_box, &st) // geometry

	press_frame(ctx, {150, 150}, build_box, &st)
	testing.expect(t, !st.clicked) // held, not released

	release_frame(ctx, build_box, &st)
	testing.expect(t, st.clicked)
}

// A grey button "gb" pinned at the origin, size {100,30} (center {50,15}).
build_gray_btn :: proc(ctx: ^wynn.Context, st: ^Box_State) {
	st.clicked = wynn.button(ctx, "gb", "OK", {100, 30}, {0.5, 0.5, 0.5, 1})
	wynn.anchor(ctx, {.Left, .Top})
}

@(test)
test_button_darkens_while_pressed :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Box_State

	frame(ctx, build_gray_btn, &st) // geometry

	// not pressed -> base colour
	d0 := wynn.render(ctx, context.allocator)
	base := d0[0].color
	delete(d0, context.allocator)
	testing.expect_value(t, base, wynn.vec4{0.5, 0.5, 0.5, 1})

	// press and hold over the button -> it becomes the active node
	wynn.input_mouse_move(ctx, {50, 15})
	wynn.input_mouse_button_down(ctx, .Left)
	frame(ctx, build_gray_btn, &st)

	d1 := wynn.render(ctx, context.allocator)
	pressed := d1[0].color
	delete(d1, context.allocator)
	testing.expect(t, pressed.r < base.r) // darker rgb
	testing.expect(t, pressed.g < base.g)
	testing.expect(t, pressed.b < base.b)
	testing.expect_value(t, pressed.a, base.a) // alpha unchanged

	// release -> back to base colour
	wynn.input_mouse_button_up(ctx, .Left)
	frame(ctx, build_gray_btn, &st)
	d2 := wynn.render(ctx, context.allocator)
	released := d2[0].color
	delete(d2, context.allocator)
	testing.expect_value(t, released, base)
}

@(test)
test_container_helpers :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	ri := len(ctx.nodes);wynn.begin_row(ctx, gap = 8);wynn.end_row(ctx)
	ci := len(ctx.nodes);wynn.begin_column(ctx, gap = 4);wynn.end_column(ctx)
	gi := len(ctx.nodes);wynn.begin_grid(ctx, 3, gap = {5, 5});wynn.end_grid(ctx)
	wynn.end_frame(ctx)

	testing.expect_value(t, ctx.nodes[ri].layout.kind, wynn.Layout_Kind.Row)
	testing.expect_value(t, ctx.nodes[ri].layout.gap, wynn.vec2{8, 0})
	testing.expect_value(t, ctx.nodes[ci].layout.kind, wynn.Layout_Kind.Column)
	testing.expect_value(t, ctx.nodes[ci].layout.gap, wynn.vec2{0, 4})
	testing.expect_value(t, ctx.nodes[gi].layout.kind, wynn.Layout_Kind.Grid)
	testing.expect_value(t, ctx.nodes[gi].layout.columns, i32(3))
}

@(test)
test_row_of_buttons_flows :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	wynn.begin_row(ctx, gap = 10)
	ai := len(ctx.nodes);wynn.button(ctx, "a", "A", {50, 30})
	bi := len(ctx.nodes);wynn.button(ctx, "b", "B", {50, 30})
	wynn.end_row(ctx)
	wynn.end_frame(ctx)

	testing.expect_value(t, ctx.nodes[ai].global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, ctx.nodes[bi].global_rect.pos, wynn.vec2{60, 0}) // 50 + 10
}
