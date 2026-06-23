package wynn_test

import "core:testing"
import wynn ".."

click_at :: proc(ctx: ^wynn.Context, p: wynn.vec2) {
	wynn.input_mouse_move(ctx, p)
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)
	wynn.input_mouse_button_up(ctx, .Left)
	wynn.process_input(ctx)
}

@(test)
test_checkbox_toggles :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	cb := wynn.checkbox(ctx, ctx.screen, checked = false, size = {20, 20})
	wynn.get_component(ctx, cb).rect.pos = {10, 10}
	wynn.process_ui(ctx)

	testing.expect_value(t, wynn.get_component(ctx, cb).value, f32(0))
	click_at(ctx, {15, 15})
	testing.expect_value(t, wynn.get_component(ctx, cb).value, f32(1)) // now checked
	click_at(ctx, {15, 15})
	testing.expect_value(t, wynn.get_component(ctx, cb).value, f32(0)) // back off
}

@(test)
test_switch_toggles :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	sw := wynn.toggle_switch(ctx, ctx.screen, on = true, size = {44, 22})
	wynn.get_component(ctx, sw).rect.pos = {0, 0}
	wynn.process_ui(ctx)

	testing.expect_value(t, wynn.get_component(ctx, sw).value, f32(1))
	click_at(ctx, {20, 10})
	testing.expect_value(t, wynn.get_component(ctx, sw).value, f32(0))
}

@(test)
test_slider_sets_value_from_cursor :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	s := wynn.slider(ctx, ctx.screen, value = 0, size = {200, 20})
	wynn.get_component(ctx, s).rect.pos = {100, 50}
	wynn.process_ui(ctx) // slider track spans x in [100, 300]

	// press at the middle of the track -> value ~0.5
	wynn.input_mouse_move(ctx, {200, 60})
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)
	testing.expect_value(t, wynn.get_component(ctx, s).value, f32(0.5))

	// drag to the far right -> clamped to 1
	wynn.input_mouse_move(ctx, {400, 60})
	wynn.process_input(ctx)
	testing.expect_value(t, wynn.get_component(ctx, s).value, f32(1))

	// release; drag past left while not held does nothing
	wynn.input_mouse_button_up(ctx, .Left)
	wynn.process_input(ctx)
	wynn.input_mouse_move(ctx, {0, 60})
	wynn.process_input(ctx)
	testing.expect_value(t, wynn.get_component(ctx, s).value, f32(1)) // unchanged after release
}

@(test)
test_slider_emits_value :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	s := wynn.slider(ctx, ctx.screen, value = 0.25)
	wynn.process_ui(ctx)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 1)
	testing.expect_value(t, data[0].value, f32(0.25))
	testing.expect(t, .Slide in data[0].traits)
}
