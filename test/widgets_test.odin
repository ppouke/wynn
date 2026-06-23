package wynn_test

import "core:testing"
import wynn ".."

@(test)
test_label :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	h := wynn.label(ctx, ctx.screen, "Hello", text_size = 18)
	c := wynn.get_component(ctx, h)

	testing.expect(t, .Text in c.traits)
	testing.expect_value(t, c.text, "Hello")
	testing.expect_value(t, c.text_size, f32(18))
	// parented under the screen
	testing.expect_value(t, c.parent, ctx.screen)
}

@(test)
test_label_emitted_with_text :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	wynn.label(ctx, ctx.screen, "Hi", text_size = 12)
	wynn.process_ui(ctx)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 1)
	testing.expect_value(t, data[0].text, "Hi")
	testing.expect_value(t, data[0].text_size, f32(12))
	testing.expect(t, .Text in data[0].traits)
}

@(test)
test_button_traits_and_size :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	h := wynn.button(ctx, ctx.screen, "OK", size = {120, 40})
	c := wynn.get_component(ctx, h)

	testing.expect(t, .Press in c.traits)
	testing.expect(t, .Text in c.traits)
	testing.expect_value(t, c.text, "OK")
	testing.expect_value(t, c.constraints.pref_size, wynn.vec2{120, 40})
}

@(test)
test_button_click :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	btn := wynn.button(ctx, ctx.screen, "OK", size = {100, 30})
	wynn.process_ui(ctx) // button at {0,0 .. 100,30}

	// press and release inside the button
	wynn.input_mouse_move(ctx, {20, 15})
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)
	testing.expect(t, !wynn.was_clicked(ctx, btn))

	wynn.input_mouse_button_up(ctx, .Left)
	wynn.process_input(ctx)
	testing.expect(t, wynn.was_clicked(ctx, btn))
}

@(test)
test_container_helpers :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	r := wynn.row(ctx, ctx.screen, gap = 8)
	col := wynn.column(ctx, ctx.screen, gap = 4)
	g := wynn.grid(ctx, ctx.screen, columns = 3, gap = {5, 5})

	testing.expect_value(t, wynn.get_component(ctx, r).layout.kind, wynn.Layout_Kind.Row)
	testing.expect_value(t, wynn.get_component(ctx, r).layout.gap, wynn.vec2{8, 0})
	testing.expect_value(t, wynn.get_component(ctx, col).layout.kind, wynn.Layout_Kind.Column)
	testing.expect_value(t, wynn.get_component(ctx, col).layout.gap, wynn.vec2{0, 4})
	testing.expect_value(t, wynn.get_component(ctx, g).layout.kind, wynn.Layout_Kind.Grid)
	testing.expect_value(t, wynn.get_component(ctx, g).layout.columns, i32(3))
}

@(test)
test_row_of_buttons_flows :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	r := wynn.row(ctx, ctx.screen, gap = 10)
	a := wynn.button(ctx, r, "A", size = {50, 30})
	b := wynn.button(ctx, r, "B", size = {50, 30})
	wynn.process_ui(ctx)

	testing.expect_value(t, wynn.get_component(ctx, a).global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, wynn.get_component(ctx, b).global_rect.pos, wynn.vec2{60, 0}) // 50 + 10
}
