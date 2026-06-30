package wynn_test

import "core:testing"
import wynn ".."

// Opens a container sized `size` (unanchored at the origin) with layout `lay`,
// emits `n` child items each of `item` size, and closes it. Must be called
// between begin_frame/end_frame; returns the container and child indices.
build_container :: proc(
	ctx: ^wynn.Context,
	size: wynn.vec2,
	lay: wynn.Layout,
	item: wynn.vec2,
	n: int,
) -> (
	parent: int,
	kids: [dynamic]int,
) {
	parent = wynn.begin_container(ctx, lay, {}, wynn.Constraints{pref_size = size})
	for _ in 0 ..< n {
		append(&kids, leaf(ctx, wynn.Constraints{pref_size = item}))
	}
	wynn.pop_container(ctx)
	return
}

@(test)
test_row_layout :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	_, kids := build_container(
		ctx,
		{400, 200},
		wynn.Layout{kind = .Row, gap = {10, 0}, padding = {left = 5, top = 5}},
		{50, 30},
		3,
	)
	wynn.end_frame(ctx)
	defer delete(kids)

	// items flow left-to-right from content origin (5,5), gap 10, width 50
	testing.expect_value(t, ctx.nodes[kids[0]].global_rect.pos, wynn.vec2{5, 5})
	testing.expect_value(t, ctx.nodes[kids[1]].global_rect.pos, wynn.vec2{65, 5}) // 5 + 50 + 10
	testing.expect_value(t, ctx.nodes[kids[2]].global_rect.pos, wynn.vec2{125, 5}) // 65 + 50 + 10
	testing.expect_value(t, ctx.nodes[kids[0]].global_rect.size, wynn.vec2{50, 30}) // measured size kept
}

@(test)
test_column_layout :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	_, kids := build_container(
		ctx,
		{200, 400},
		wynn.Layout{kind = .Column, gap = {0, 8}},
		{60, 40},
		3,
	)
	wynn.end_frame(ctx)
	defer delete(kids)

	testing.expect_value(t, ctx.nodes[kids[0]].global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, ctx.nodes[kids[1]].global_rect.pos, wynn.vec2{0, 48}) // 0 + 40 + 8
	testing.expect_value(t, ctx.nodes[kids[2]].global_rect.pos, wynn.vec2{0, 96}) // 48 + 40 + 8
}

@(test)
test_grid_layout :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	// 300-wide content, 2 columns, gap 20 -> col_w = (300 - 20)/2 = 140
	wynn.begin_frame(ctx, SCREEN)
	_, kids := build_container(
		ctx,
		{300, 300},
		wynn.Layout{kind = .Grid, columns = 2, gap = {20, 10}},
		{50, 50},
		4,
	)
	wynn.end_frame(ctx)
	defer delete(kids)

	r := [4]wynn.Rect{}
	for k, i in kids {
		r[i] = ctx.nodes[k].global_rect
	}
	// row 0
	testing.expect_value(t, r[0].pos, wynn.vec2{0, 0})
	testing.expect_value(t, r[1].pos, wynn.vec2{160, 0}) // col 1 at 140+20
	// row 1: row height = 50, gap 10 -> y = 60
	testing.expect_value(t, r[2].pos, wynn.vec2{0, 60})
	testing.expect_value(t, r[3].pos, wynn.vec2{160, 60})
}

@(test)
test_layout_overrides_child_anchors :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	wynn.begin_frame(ctx, SCREEN)
	wynn.begin_container(ctx, wynn.Layout{kind = .Row}, {}, wynn.Constraints{pref_size = {400, 200}})
	// child sets anchors that would otherwise pin it bottom-right; the row
	// layout must ignore them and place it at the content origin.
	child := leaf(ctx, wynn.Constraints {
		anchors   = {.Right, .Bottom},
		margins   = {right = 10, bottom = 10},
		pref_size = {50, 50},
	})
	wynn.pop_container(ctx)
	wynn.end_frame(ctx)

	testing.expect_value(t, ctx.nodes[child].global_rect.pos, wynn.vec2{0, 0})
}

@(test)
test_nested_containers :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)

	// outer column holds an inner row; inner row holds two items
	wynn.begin_frame(ctx, SCREEN)
	wynn.begin_container(ctx, wynn.Layout{kind = .Column, gap = {0, 10}}, {}, wynn.Constraints{pref_size = {400, 400}})
	inner := wynn.begin_container(ctx, wynn.Layout{kind = .Row, gap = {5, 0}}, {}, wynn.Constraints{pref_size = {300, 40}})
	a := leaf(ctx, wynn.Constraints{pref_size = {30, 30}})
	b := leaf(ctx, wynn.Constraints{pref_size = {30, 30}})
	wynn.pop_container(ctx) // inner
	wynn.pop_container(ctx) // outer
	wynn.end_frame(ctx)

	// inner is first column item at {0,0}; row items flow inside it
	testing.expect_value(t, ctx.nodes[inner].global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, ctx.nodes[a].global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, ctx.nodes[b].global_rect.pos, wynn.vec2{35, 0}) // 30 + 5
}
