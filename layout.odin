package wynn

// ----------------------------------------------------------------------------
// Layout solver
//
// Two passes over the tree:
//   1. measure (bottom-up): each node resolves its intrinsic size from its own
//      constraints (pref clamped to min/max) and stores it in `rect.size`.
//      Children are measured first so content-driven sizing can be added here
//      later without changing the arrange pass.
//   2. arrange (top-down): each node resolves its absolute `global_rect` from
//      its anchors/margins against the parent's already-resolved global rect.
//
// The screen root keeps the rect set by initialize/update_screen_size and is
// never resized by constraints; its children are arranged within it.
// ----------------------------------------------------------------------------

// Recomputes geometry for the entire tree. Call once per frame.
solve_layout :: proc(ctx: ^Context) {
	root := get_component(ctx, ctx.screen)
	root.global_rect = root.rect // root fills the screen

	child := root.first_child
	for !handle_is_null(child) {
		measure(ctx, child)
		child = get_component(ctx, child).next_sibling
	}

	arrange_children(ctx, ctx.screen)
}

// Bottom-up pass: resolve intrinsic size for `handle` and its subtree.
measure :: proc(ctx: ^Context, handle: Handle) {
	c := get_component(ctx, handle)

	child := c.first_child
	for !handle_is_null(child) {
		measure(ctx, child)
		child = get_component(ctx, child).next_sibling
	}

	c.rect.size = clamp_size(c.constraints)
}

// Top-down pass: position `parent`'s direct children, then recurse into each
// child's subtree. A container with a layout kind flows its children and
// ignores their anchors; otherwise children resolve by their own anchors.
arrange_children :: proc(ctx: ^Context, parent: Handle) {
	p := get_component(ctx, parent)
	parent_rect := p.global_rect

	if p.layout.kind == .None {
		child := p.first_child
		for !handle_is_null(child) {
			cc := get_component(ctx, child)
			arrange_one(cc, parent_rect)
			child = cc.next_sibling
		}
	} else {
		arrange_flow(ctx, p, parent_rect)
	}

	// Recurse into each child's own subtree.
	child := p.first_child
	for !handle_is_null(child) {
		arrange_children(ctx, child)
		child = get_component(ctx, child).next_sibling
	}
}

// Positions all children of a container node by its layout kind. Each child
// keeps its measured size (`rect.size`); positions are laid out within the
// parent's content rect (parent rect inset by `padding`).
@(private = "file")
arrange_flow :: proc(ctx: ^Context, p: ^Component, prect: Rect) {
	lay := p.layout

	// Content origin/extent after padding.
	cx := prect.pos.x + lay.padding.left
	cy := prect.pos.y + lay.padding.top
	cw := prect.size.x - lay.padding.left - lay.padding.right
	if cw < 0 {
		cw = 0
	}

	switch lay.kind {
	case .None:
	// handled by caller; nothing to do here
	case .Row:
		x := cx
		child := p.first_child
		for !handle_is_null(child) {
			cc := get_component(ctx, child)
			cc.global_rect = Rect{pos = {x, cy}, size = cc.rect.size}
			x += cc.rect.size.x + lay.gap.x
			child = cc.next_sibling
		}
	case .Column:
		y := cy
		child := p.first_child
		for !handle_is_null(child) {
			cc := get_component(ctx, child)
			cc.global_rect = Rect{pos = {cx, y}, size = cc.rect.size}
			y += cc.rect.size.y + lay.gap.y
			child = cc.next_sibling
		}
	case .Grid:
		cols := lay.columns
		if cols < 1 {
			cols = 1
		}
		col_w := (cw - lay.gap.x * f32(cols - 1)) / f32(cols)
		if col_w < 0 {
			col_w = 0
		}

		i: i32 = 0
		row_y := cy
		row_h: f32 = 0 // tallest item in the current row
		child := p.first_child
		for !handle_is_null(child) {
			cc := get_component(ctx, child)
			col := i % cols
			cell_x := cx + f32(col) * (col_w + lay.gap.x)
			cc.global_rect = Rect{pos = {cell_x, row_y}, size = cc.rect.size}
			if cc.rect.size.y > row_h {
				row_h = cc.rect.size.y
			}
			if col == cols - 1 { 	// last column: advance to next row
				row_y += row_h + lay.gap.y
				row_h = 0
			}
			i += 1
			child = cc.next_sibling
		}
	}
}

// Resolves one component's absolute rect from its constraints and the parent's
// resolved rect.
arrange_one :: proc(c: ^Component, parent: Rect) {
	cons := c.constraints

	x, w := resolve_axis(
		.Left in cons.anchors,
		.Right in cons.anchors,
		cons.margins.left,
		cons.margins.right,
		parent.pos.x,
		parent.size.x,
		c.rect.pos.x,
		c.rect.size.x,
	)
	y, h := resolve_axis(
		.Top in cons.anchors,
		.Bottom in cons.anchors,
		cons.margins.top,
		cons.margins.bottom,
		parent.pos.y,
		parent.size.y,
		c.rect.pos.y,
		c.rect.size.y,
	)

	c.global_rect = Rect{pos = {x, y}, size = {w, h}}
}

// Resolves position and size on a single axis.
//   - both edges anchored: stretch to fill the parent minus margins.
//   - low edge only:  pin to the low edge + margin, keep measured size.
//   - high edge only: pin to the high edge - margin, keep measured size.
//   - neither:        place at parent origin + local offset, keep measured size.
@(private = "file")
resolve_axis :: proc(
	a_lo, a_hi: bool,
	m_lo, m_hi: f32,
	p_pos, p_size: f32,
	local_pos, size: f32,
) -> (
	pos: f32,
	out_size: f32,
) {
	switch {
	case a_lo && a_hi:
		pos = p_pos + m_lo
		out_size = p_size - m_lo - m_hi
		if out_size < 0 {
			out_size = 0
		}
	case a_lo:
		pos = p_pos + m_lo
		out_size = size
	case a_hi:
		out_size = size
		pos = p_pos + p_size - m_hi - size
	case:
		pos = p_pos + local_pos
		out_size = size
	}
	return
}

// Clamps preferred size to [min, max] per axis. A max component of 0 means
// unbounded on that axis.
clamp_size :: proc(cons: Constraints) -> vec2 {
	return vec2{
		clamp_axis(cons.pref_size.x, cons.min_size.x, cons.max_size.x),
		clamp_axis(cons.pref_size.y, cons.min_size.y, cons.max_size.y),
	}
}

// Reports whether point `p` lies within rect `r` (edges inclusive).
rect_contains :: proc(r: Rect, p: vec2) -> bool {
	return(
		p.x >= r.pos.x &&
		p.x <= r.pos.x + r.size.x &&
		p.y >= r.pos.y &&
		p.y <= r.pos.y + r.size.y \
	)
}

@(private = "file")
clamp_axis :: proc(pref, min, max: f32) -> f32 {
	v := pref
	if v < min {
		v = min
	}
	if max > 0 && v > max {
		v = max
	}
	return v
}
