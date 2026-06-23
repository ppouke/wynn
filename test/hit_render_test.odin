package wynn_test

import "core:testing"
import wynn ".."

// Two overlapping children of the screen, A under B.
// A: {0,0 .. 100,100}, B: {50,50 .. 150,150}.
setup_overlap :: proc(ctx: ^wynn.Context) -> (a, b: wynn.Handle) {
	a = make(ctx, ctx.screen, wynn.Constraints{pref_size = {100, 100}})
	wynn.get_component(ctx, a).rect.pos = {0, 0}

	b = make(ctx, ctx.screen, wynn.Constraints{pref_size = {100, 100}})
	wynn.get_component(ctx, b).rect.pos = {50, 50}

	wynn.process_ui(ctx)
	return
}

@(test)
test_hit_topmost_wins :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	a, b := setup_overlap(ctx)

	// overlap region -> B (added last, drawn on top)
	testing.expect_value(t, wynn.hit_test(ctx, {75, 75}), b)
	// only A
	testing.expect_value(t, wynn.hit_test(ctx, {25, 25}), a)
}

@(test)
test_hit_empty_returns_screen :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	setup_overlap(ctx)

	testing.expect_value(t, wynn.hit_test(ctx, {400, 400}), ctx.screen)
}

@(test)
test_hit_outside_screen_is_null :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	setup_overlap(ctx)

	testing.expect_value(t, wynn.hit_test(ctx, {-5, -5}), wynn.NULL_HANDLE)
}

@(test)
test_hit_deepest_child :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	parent := make(ctx, ctx.screen, wynn.Constraints{pref_size = {200, 200}})
	wynn.get_component(ctx, parent).rect.pos = {10, 10}
	child := make(ctx, parent, wynn.Constraints{pref_size = {50, 50}})
	wynn.get_component(ctx, child).rect.pos = {5, 5}

	wynn.process_ui(ctx)

	// child global rect is {15,15 .. 65,65}; point inside hits the child
	testing.expect_value(t, wynn.hit_test(ctx, {20, 20}), child)
	// point inside parent but outside child hits the parent
	testing.expect_value(t, wynn.hit_test(ctx, {100, 100}), parent)
}

@(test)
test_render_emits_visible_in_order :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	a, b := setup_overlap(ctx)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 2)
	testing.expect_value(t, data[0].rect, wynn.get_component(ctx, a).global_rect)
	testing.expect_value(t, data[1].rect, wynn.get_component(ctx, b).global_rect)
}

@(test)
test_render_skips_hidden_subtree :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	parent := make(ctx, ctx.screen, wynn.Constraints{pref_size = {100, 100}})
	make(ctx, parent, wynn.Constraints{pref_size = {20, 20}}) // child
	wynn.get_component(ctx, parent).visible = false

	wynn.process_ui(ctx)
	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	// hidden parent hides itself and its child
	testing.expect_value(t, len(data), 0)
}
