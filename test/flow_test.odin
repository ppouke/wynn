package wynn_test

import "core:testing"
import wynn ".."

// A container at {0,0} sized `size`, with the given layout, plus `n` child
// items each of `item` size. Returns the container and a slice of children.
container :: proc(
	ctx: ^wynn.Context,
	size: wynn.vec2,
	lay: wynn.Layout,
	item: wynn.vec2,
	n: int,
) -> (
	parent: wynn.Handle,
	kids: [dynamic]wynn.Handle,
) {
	parent = make(ctx, ctx.screen, wynn.Constraints{anchors = {.Left, .Top, .Right, .Bottom}})
	// pin the container to the full screen minus a margin so its rect == size
	pc := wynn.get_component(ctx, parent)
	pc.constraints.margins = {0, 0, 800 - size.x, 600 - size.y}
	pc.layout = lay

	for _ in 0 ..< n {
		k := make(ctx, parent, wynn.Constraints{pref_size = item})
		append(&kids, k)
	}
	wynn.process_ui(ctx)
	return
}

@(test)
test_row_layout :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	parent, kids := container(
		ctx,
		{400, 200},
		wynn.Layout{kind = .Row, gap = {10, 0}, padding = {left = 5, top = 5}},
		{50, 30},
		3,
	)
	defer delete(kids)

	// items flow left-to-right from content origin (5,5), gap 10, width 50
	r0 := wynn.get_component(ctx, kids[0]).global_rect
	r1 := wynn.get_component(ctx, kids[1]).global_rect
	r2 := wynn.get_component(ctx, kids[2]).global_rect
	testing.expect_value(t, r0.pos, wynn.vec2{5, 5})
	testing.expect_value(t, r1.pos, wynn.vec2{65, 5}) // 5 + 50 + 10
	testing.expect_value(t, r2.pos, wynn.vec2{125, 5}) // 65 + 50 + 10
	testing.expect_value(t, r0.size, wynn.vec2{50, 30}) // measured size kept
	_ = parent
}

@(test)
test_column_layout :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	_, kids := container(
		ctx,
		{200, 400},
		wynn.Layout{kind = .Column, gap = {0, 8}},
		{60, 40},
		3,
	)
	defer delete(kids)

	r0 := wynn.get_component(ctx, kids[0]).global_rect
	r1 := wynn.get_component(ctx, kids[1]).global_rect
	r2 := wynn.get_component(ctx, kids[2]).global_rect
	testing.expect_value(t, r0.pos, wynn.vec2{0, 0})
	testing.expect_value(t, r1.pos, wynn.vec2{0, 48}) // 0 + 40 + 8
	testing.expect_value(t, r2.pos, wynn.vec2{0, 96}) // 48 + 40 + 8
}

@(test)
test_grid_layout :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	// 300-wide content, 2 columns, gap 20 -> col_w = (300 - 20)/2 = 140
	_, kids := container(
		ctx,
		{300, 300},
		wynn.Layout{kind = .Grid, columns = 2, gap = {20, 10}},
		{50, 50},
		4,
	)
	defer delete(kids)

	r := [4]wynn.Rect{}
	for k, i in kids {
		r[i] = wynn.get_component(ctx, k).global_rect
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
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	parent := make(ctx, ctx.screen, wynn.Constraints{anchors = {.Left, .Top, .Right, .Bottom}})
	pc := wynn.get_component(ctx, parent)
	pc.constraints.margins = {0, 0, 800 - 400, 600 - 200}
	pc.layout = wynn.Layout{kind = .Row}

	// child sets anchors that would otherwise pin it bottom-right; the row
	// layout must ignore them and place it at the content origin.
	child := make(ctx, parent, wynn.Constraints{
		anchors   = {.Right, .Bottom},
		margins   = {right = 10, bottom = 10},
		pref_size = {50, 50},
	})
	wynn.process_ui(ctx)

	testing.expect_value(t, wynn.get_component(ctx, child).global_rect.pos, wynn.vec2{0, 0})
}

@(test)
test_nested_containers :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)

	// outer column holds an inner row; inner row holds two items
	outer := make(ctx, ctx.screen, wynn.Constraints{anchors = {.Left, .Top, .Right, .Bottom}})
	wynn.get_component(ctx, outer).constraints.margins = {0, 0, 800 - 400, 600 - 400}
	wynn.get_component(ctx, outer).layout = wynn.Layout{kind = .Column, gap = {0, 10}}

	inner := make(ctx, outer, wynn.Constraints{pref_size = {300, 40}})
	wynn.get_component(ctx, inner).layout = wynn.Layout{kind = .Row, gap = {5, 0}}

	a := make(ctx, inner, wynn.Constraints{pref_size = {30, 30}})
	b := make(ctx, inner, wynn.Constraints{pref_size = {30, 30}})

	wynn.process_ui(ctx)

	// inner is first column item at {0,0}; row items flow inside it
	testing.expect_value(t, wynn.get_component(ctx, inner).global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, wynn.get_component(ctx, a).global_rect.pos, wynn.vec2{0, 0})
	testing.expect_value(t, wynn.get_component(ctx, b).global_rect.pos, wynn.vec2{35, 0}) // 30 + 5
}
