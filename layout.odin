package wynn

// ----------------------------------------------------------------------------
// Layout solver (operates on the current frame's node arena)
//
// Two passes: measure (bottom-up intrinsic size) then arrange (top-down,
// resolving anchors/flow into global_rect). Node 0 is the screen root and keeps
// its frame size. The math is identical to the retained version; it just walks
// node indices instead of handles. No nodes are appended during the solve, so
// holding node pointers within a pass is safe.
// ----------------------------------------------------------------------------

solve_layout :: proc(ctx: ^Context) {
	if len(ctx.nodes) == 0 {
		return
	}
	ctx.nodes[0].global_rect = ctx.nodes[0].rect // root fills the screen

	child := ctx.nodes[0].first_child
	for child != NO_NODE {
		measure(ctx, child)
		child = ctx.nodes[child].next_sibling
	}
	arrange_children(ctx, 0)
}

// Bottom-up: resolve intrinsic size for `idx` and its subtree.
measure :: proc(ctx: ^Context, idx: int) {
	child := ctx.nodes[idx].first_child
	for child != NO_NODE {
		measure(ctx, child)
		child = ctx.nodes[child].next_sibling
	}
	ctx.nodes[idx].rect.size = clamp_size(ctx.nodes[idx].constraints)
}

// Top-down: position `parent`'s direct children, then recurse. A container with
// a layout kind flows its children and ignores their anchors.
arrange_children :: proc(ctx: ^Context, parent: int) {
	parent_rect := ctx.nodes[parent].global_rect

	if ctx.nodes[parent].layout.kind == .None {
		child := ctx.nodes[parent].first_child
		for child != NO_NODE {
			arrange_one(ctx, child, parent_rect)
			child = ctx.nodes[child].next_sibling
		}
	} else {
		arrange_flow(ctx, parent, parent_rect)
	}

	child := ctx.nodes[parent].first_child
	for child != NO_NODE {
		arrange_children(ctx, child)
		child = ctx.nodes[child].next_sibling
	}
}

// Resolves one node's absolute rect from its constraints and the parent's rect.
arrange_one :: proc(ctx: ^Context, idx: int, parent: Rect) {
	cons := ctx.nodes[idx].constraints

	x, w := resolve_axis(
		.Left in cons.anchors,
		.Right in cons.anchors,
		cons.margins.left,
		cons.margins.right,
		parent.pos.x,
		parent.size.x,
		ctx.nodes[idx].rect.pos.x,
		ctx.nodes[idx].rect.size.x,
	)
	y, h := resolve_axis(
		.Top in cons.anchors,
		.Bottom in cons.anchors,
		cons.margins.top,
		cons.margins.bottom,
		parent.pos.y,
		parent.size.y,
		ctx.nodes[idx].rect.pos.y,
		ctx.nodes[idx].rect.size.y,
	)

	ctx.nodes[idx].global_rect = Rect{pos = {x, y}, size = {w, h}}
}

// Positions all children of a container by its layout kind. Each child keeps
// its measured size; positions are within the parent's content rect (parent
// rect inset by padding).
@(private = "file")
arrange_flow :: proc(ctx: ^Context, parent: int, prect: Rect) {
	lay := ctx.nodes[parent].layout

	cx := prect.pos.x + lay.padding.left
	cy := prect.pos.y + lay.padding.top
	cw := prect.size.x - lay.padding.left - lay.padding.right
	if cw < 0 {
		cw = 0
	}

	switch lay.kind {
	case .None:
	// handled by caller
	case .Row:
		x := cx
		child := ctx.nodes[parent].first_child
		for child != NO_NODE {
			sz := ctx.nodes[child].rect.size
			ctx.nodes[child].global_rect = Rect{pos = {x, cy}, size = sz}
			x += sz.x + lay.gap.x
			child = ctx.nodes[child].next_sibling
		}
	case .Column:
		y := cy
		child := ctx.nodes[parent].first_child
		for child != NO_NODE {
			sz := ctx.nodes[child].rect.size
			ctx.nodes[child].global_rect = Rect{pos = {cx, y}, size = sz}
			y += sz.y + lay.gap.y
			child = ctx.nodes[child].next_sibling
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
		row_h: f32 = 0
		child := ctx.nodes[parent].first_child
		for child != NO_NODE {
			sz := ctx.nodes[child].rect.size
			col := i % cols
			cell_x := cx + f32(col) * (col_w + lay.gap.x)
			ctx.nodes[child].global_rect = Rect{pos = {cell_x, row_y}, size = sz}
			if sz.y > row_h {
				row_h = sz.y
			}
			if col == cols - 1 {
				row_y += row_h + lay.gap.y
				row_h = 0
			}
			i += 1
			child = ctx.nodes[child].next_sibling
		}
	}
}

// Resolves position and size on a single axis (see retained DESIGN §8).
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
	return vec2 {
		clamp_axis(cons.pref_size.x, cons.min_size.x, cons.max_size.x),
		clamp_axis(cons.pref_size.y, cons.min_size.y, cons.max_size.y),
	}
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

// Reports whether point `p` lies within rect `r` (edges inclusive).
rect_contains :: proc(r: Rect, p: vec2) -> bool {
	return(
		p.x >= r.pos.x &&
		p.x <= r.pos.x + r.size.x &&
		p.y >= r.pos.y &&
		p.y <= r.pos.y + r.size.y \
	)
}
