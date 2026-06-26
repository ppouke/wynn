package wynn_test

import "core:testing"
import wynn ".."

// Layout is solved by end_frame; afterwards the solved tree lives in ctx.nodes
// (the swap into prev_nodes happens at the next begin_frame), so a node's
// resolved geometry is read as ctx.nodes[idx].global_rect.

@(test)
test_stretch_both_edges :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	h := leaf(ctx, wynn.Constraints {
		anchors = {.Left, .Top, .Right, .Bottom},
		margins = {left = 10, top = 10, right = 10, bottom = 10},
	})
	wynn.end_frame(ctx)

	r := ctx.nodes[h].global_rect
	testing.expect_value(t, r.pos, wynn.vec2{10, 10})
	testing.expect_value(t, r.size, wynn.vec2{780, 580})
}

@(test)
test_anchor_low_edges :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	h := leaf(ctx, wynn.Constraints {
		anchors   = {.Left, .Top},
		margins   = {left = 20, top = 30},
		pref_size = {100, 50},
	})
	wynn.end_frame(ctx)

	r := ctx.nodes[h].global_rect
	testing.expect_value(t, r.pos, wynn.vec2{20, 30})
	testing.expect_value(t, r.size, wynn.vec2{100, 50})
}

@(test)
test_anchor_high_edges :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	h := leaf(ctx, wynn.Constraints {
		anchors   = {.Right, .Bottom},
		margins   = {right = 10, bottom = 10},
		pref_size = {100, 50},
	})
	wynn.end_frame(ctx)

	r := ctx.nodes[h].global_rect
	// x = 800 - 10 - 100 = 690 ; y = 600 - 10 - 50 = 540
	testing.expect_value(t, r.pos, wynn.vec2{690, 540})
	testing.expect_value(t, r.size, wynn.vec2{100, 50})
}

@(test)
test_unanchored_uses_local_offset :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	h := leaf(ctx, wynn.Constraints{pref_size = {40, 40}})
	ctx.nodes[h].rect.pos = {5, 7}
	wynn.end_frame(ctx)

	r := ctx.nodes[h].global_rect
	testing.expect_value(t, r.pos, wynn.vec2{5, 7})
	testing.expect_value(t, r.size, wynn.vec2{40, 40})
}

@(test)
test_min_max_clamp :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	// pref above max on x, below min on y
	wynn.begin_frame(ctx, SCREEN)
	h := leaf(ctx, wynn.Constraints {
		anchors   = {.Left, .Top},
		min_size  = {0, 30},
		max_size  = {150, 0}, // x capped at 150, y unbounded
		pref_size = {200, 10},
	})
	wynn.end_frame(ctx)

	r := ctx.nodes[h].global_rect
	testing.expect_value(t, r.size, wynn.vec2{150, 30})
}

@(test)
test_nested_resolves_against_parent :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	// parent: stretch with margin 100 -> pos {100,100}, size {600,400}
	parent := wynn.begin_container(ctx, wynn.Layout{}, {}, wynn.Constraints {
		anchors = {.Left, .Top, .Right, .Bottom},
		margins = {left = 100, top = 100, right = 100, bottom = 100},
	})
	// child: anchored top-left of parent with margin 10
	child := leaf(ctx, wynn.Constraints {
		anchors   = {.Left, .Top},
		margins   = {left = 10, top = 10},
		pref_size = {50, 50},
	})
	wynn.pop_container(ctx)
	wynn.end_frame(ctx)

	pr := ctx.nodes[parent].global_rect
	testing.expect_value(t, pr.pos, wynn.vec2{100, 100})
	testing.expect_value(t, pr.size, wynn.vec2{600, 400})

	cr := ctx.nodes[child].global_rect
	// child pos = parent.pos + margin = {110, 110}
	testing.expect_value(t, cr.pos, wynn.vec2{110, 110})
	testing.expect_value(t, cr.size, wynn.vec2{50, 50})
}
