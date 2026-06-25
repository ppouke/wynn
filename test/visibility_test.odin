package wynn_test

import "core:testing"
import wynn ".."

@(test)
test_mouse_over_ui :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	btn := wynn.button(ctx, ctx.screen, "OK", size = {100, 30}) // at {0,0 .. 100,30}
	wynn.process_ui(ctx)

	// over the button -> true
	wynn.input_mouse_move(ctx, {20, 15})
	wynn.process_input(ctx)
	testing.expect(t, wynn.mouse_over_ui(ctx))

	// over empty background (resolves to the screen root) -> false
	wynn.input_mouse_move(ctx, {400, 400})
	wynn.process_input(ctx)
	testing.expect(t, !wynn.mouse_over_ui(ctx))

	// outside the window entirely -> false
	wynn.input_mouse_move(ctx, {-5, -5})
	wynn.process_input(ctx)
	testing.expect(t, !wynn.mouse_over_ui(ctx))

	// hidden component does not count (hit-testing skips it)
	wynn.get_component(ctx, btn).visible = false
	wynn.process_ui(ctx)
	wynn.input_mouse_move(ctx, {20, 15})
	wynn.process_input(ctx)
	testing.expect(t, !wynn.mouse_over_ui(ctx))
}

// A hidden parent hides its whole subtree for hit-testing too (not just render).
@(test)
test_hidden_parent_blocks_child_hit :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	parent := wynn.new_child(ctx, ctx.screen)
	wynn.get_component(ctx, parent).constraints.pref_size = {200, 200}
	child := wynn.new_child(ctx, parent)
	cc := wynn.get_component(ctx, child)
	cc.constraints.pref_size = {50, 50}
	cc.rect.pos = {10, 10}
	wynn.process_ui(ctx)

	// child resolves to {10,10 .. 60,60}; a point in it hits the child
	testing.expect_value(t, wynn.hit_test(ctx, {20, 20}), child)

	// hiding the parent makes the point fall through to the screen background
	wynn.get_component(ctx, parent).visible = false
	testing.expect_value(t, wynn.hit_test(ctx, {20, 20}), ctx.screen)
}
