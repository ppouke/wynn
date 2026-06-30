package wynn_test

import "core:testing"
import wynn ".."

// hit_test resolves against prev_nodes (last frame's solved geometry), so these
// tests run two identical frames: after the second, prev_nodes holds the static
// geometry and ctx.nodes holds the (identical) current frame used for render.
settle :: proc(ctx: ^wynn.Context, build: proc(ctx: ^wynn.Context)) {
	wynn.begin_frame(ctx, SCREEN);build(ctx);wynn.end_frame(ctx)
	wynn.begin_frame(ctx, SCREEN);build(ctx);wynn.end_frame(ctx)
}

// Two overlapping children of the screen root, A under B (lower index = drawn
// first / underneath). A: {0,0 .. 100,100}, B: {50,50 .. 150,150}.
// Node indices: root = 0, A = 1, B = 2.
build_overlap :: proc(ctx: ^wynn.Context) {
	a := leaf(ctx, wynn.Constraints{pref_size = {100, 100}})
	ctx.nodes[a].rect.pos = {0, 0}
	ctx.nodes[a].color = {1, 0, 0, 1}
	b := leaf(ctx, wynn.Constraints{pref_size = {100, 100}})
	ctx.nodes[b].rect.pos = {50, 50}
	ctx.nodes[b].color = {0, 1, 0, 1}
}

@(test)
test_hit_topmost_wins :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	settle(ctx, build_overlap)

	// overlap region -> B (index 2, emitted last, drawn on top)
	testing.expect_value(t, wynn.hit_test(ctx, {75, 75}), 2)
	// only A (index 1)
	testing.expect_value(t, wynn.hit_test(ctx, {25, 25}), 1)
}

@(test)
test_hit_empty_returns_no_node :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	settle(ctx, build_overlap)

	// background (only the screen root is under the point) -> NO_NODE
	testing.expect_value(t, wynn.hit_test(ctx, {400, 400}), wynn.NO_NODE)
}

@(test)
test_hit_outside_screen_is_no_node :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	settle(ctx, build_overlap)

	testing.expect_value(t, wynn.hit_test(ctx, {-5, -5}), wynn.NO_NODE)
}

// parent {10,10 .. 210,210} holds a child at local {5,5} size {50,50}
// -> child global {15,15 .. 65,65}. Indices: root 0, parent 1, child 2.
build_nested :: proc(ctx: ^wynn.Context) {
	p := wynn.begin_container(ctx, wynn.Layout{}, {}, wynn.Constraints{pref_size = {200, 200}})
	ctx.nodes[p].rect.pos = {10, 10}
	c := leaf(ctx, wynn.Constraints{pref_size = {50, 50}})
	ctx.nodes[c].rect.pos = {5, 5}
	wynn.pop_container(ctx)
}

@(test)
test_hit_deepest_child :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	settle(ctx, build_nested)

	// point inside the child hits the child (index 2)
	testing.expect_value(t, wynn.hit_test(ctx, {20, 20}), 2)
	// point inside parent but outside child hits the parent (index 1)
	testing.expect_value(t, wynn.hit_test(ctx, {100, 100}), 1)
}

@(test)
test_render_emits_in_order :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	settle(ctx, build_overlap)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 2)
	testing.expect_value(t, data[0].rect, ctx.nodes[1].global_rect) // A first
	testing.expect_value(t, data[1].rect, ctx.nodes[2].global_rect) // B on top
}

// An overlay (layer 1) emitted *before* normal content (layer 0) must still be
// drawn last, since render emits layer by layer.
build_overlay_then_panel :: proc(ctx: ^wynn.Context) {
	wynn.begin_overlay(ctx, {0, 0}, {50, 50}, {1, 0, 0, 1}) // red, layer 1
	wynn.end_overlay(ctx)
	wynn.begin_panel(ctx, color = {0, 1, 0, 1}, constraints = {pref_size = {60, 60}}) // green, layer 0
	wynn.end_panel(ctx)
}

@(test)
test_render_overlay_drawn_last :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	settle(ctx, build_overlay_then_panel)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 2)
	testing.expect_value(t, data[0].color, wynn.vec4{0, 1, 0, 1}) // normal layer first
	testing.expect_value(t, data[1].color, wynn.vec4{1, 0, 0, 1}) // overlay drawn last
}
