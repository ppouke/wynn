package wynn

import "core:mem"

// ----------------------------------------------------------------------------
// Render-data emission
//
// Walks the resolved tree top-down in painter's order (parent before child,
// siblings first -> last, so the last sibling draws on top) and produces a
// flat slice with one Render_Data entry per visible component. An invisible
// node hides its whole subtree. The screen root is not emitted; emission
// starts at its children.
//
// The returned slice is allocated with `allocator`; the caller owns it and
// frees it (e.g. `delete(data, allocator)`) when done.
// ----------------------------------------------------------------------------

render :: proc(ctx: ^Context, allocator: mem.Allocator) -> []Render_Data {
	out := make([dynamic]Render_Data, allocator)

	child := get_component(ctx, ctx.screen).first_child
	for !handle_is_null(child) {
		emit_node(ctx, child, &out)
		child = get_component(ctx, child).next_sibling
	}

	return out[:]
}

@(private = "file")
emit_node :: proc(ctx: ^Context, handle: Handle, out: ^[dynamic]Render_Data) {
	c := get_component(ctx, handle)
	if !c.visible {
		return // hidden node hides its subtree
	}

	append(
		out,
		Render_Data {
			traits = c.traits,
			rect = c.global_rect,
			color = c.color,
			text = c.text,
			text_size = c.text_size,
			value = c.value,
		},
	)

	child := c.first_child
	for !handle_is_null(child) {
		emit_node(ctx, child, out)
		child = get_component(ctx, child).next_sibling
	}
}
