package wynn_test

import "core:testing"
import wynn ".."

// Helper: create a child under `parent` with the given constraints.
make :: proc(ctx: ^wynn.Context, parent: wynn.Handle, cons: wynn.Constraints) -> wynn.Handle {
	h := wynn.add_component(ctx)
	wynn.set_parent(ctx, h, parent)
	wynn.get_component(ctx, h).constraints = cons
	return h
}

@(test)
test_stretch_both_edges :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	h := make(ctx, ctx.screen, wynn.Constraints{
		anchors = {.Left, .Top, .Right, .Bottom},
		margins = {left = 10, top = 10, right = 10, bottom = 10},
	})

	wynn.process_ui(ctx)

	r := wynn.get_component(ctx, h).global_rect
	testing.expect_value(t, r.pos, wynn.vec2{10, 10})
	testing.expect_value(t, r.size, wynn.vec2{780, 580})
}

@(test)
test_anchor_low_edges :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	h := make(ctx, ctx.screen, wynn.Constraints{
		anchors   = {.Left, .Top},
		margins   = {left = 20, top = 30},
		pref_size = {100, 50},
	})

	wynn.process_ui(ctx)

	r := wynn.get_component(ctx, h).global_rect
	testing.expect_value(t, r.pos, wynn.vec2{20, 30})
	testing.expect_value(t, r.size, wynn.vec2{100, 50})
}

@(test)
test_anchor_high_edges :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	h := make(ctx, ctx.screen, wynn.Constraints{
		anchors   = {.Right, .Bottom},
		margins   = {right = 10, bottom = 10},
		pref_size = {100, 50},
	})

	wynn.process_ui(ctx)

	r := wynn.get_component(ctx, h).global_rect
	// x = 800 - 10 - 100 = 690 ; y = 600 - 10 - 50 = 540
	testing.expect_value(t, r.pos, wynn.vec2{690, 540})
	testing.expect_value(t, r.size, wynn.vec2{100, 50})
}

@(test)
test_unanchored_uses_local_offset :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	h := make(ctx, ctx.screen, wynn.Constraints{pref_size = {40, 40}})
	c := wynn.get_component(ctx, h)
	c.rect.pos = {5, 7}

	wynn.process_ui(ctx)

	r := wynn.get_component(ctx, h).global_rect
	testing.expect_value(t, r.pos, wynn.vec2{5, 7})
	testing.expect_value(t, r.size, wynn.vec2{40, 40})
}

@(test)
test_min_max_clamp :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	// pref above max on x, below min on y
	h := make(ctx, ctx.screen, wynn.Constraints{
		anchors   = {.Left, .Top},
		min_size  = {0, 30},
		max_size  = {150, 0}, // x capped at 150, y unbounded
		pref_size = {200, 10},
	})

	wynn.process_ui(ctx)

	r := wynn.get_component(ctx, h).global_rect
	testing.expect_value(t, r.size, wynn.vec2{150, 30})
}

@(test)
test_nested_resolves_against_parent :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	// parent: stretch with margin 100 -> pos {100,100}, size {600,400}
	parent := make(ctx, ctx.screen, wynn.Constraints{
		anchors = {.Left, .Top, .Right, .Bottom},
		margins = {left = 100, top = 100, right = 100, bottom = 100},
	})
	// child: anchored top-left of parent with margin 10
	child := make(ctx, parent, wynn.Constraints{
		anchors   = {.Left, .Top},
		margins   = {left = 10, top = 10},
		pref_size = {50, 50},
	})

	wynn.process_ui(ctx)

	pr := wynn.get_component(ctx, parent).global_rect
	testing.expect_value(t, pr.pos, wynn.vec2{100, 100})
	testing.expect_value(t, pr.size, wynn.vec2{600, 400})

	cr := wynn.get_component(ctx, child).global_rect
	// child pos = parent.pos + margin = {110, 110}
	testing.expect_value(t, cr.pos, wynn.vec2{110, 110})
	testing.expect_value(t, cr.size, wynn.vec2{50, 50})
}
