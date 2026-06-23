package wynn

// ----------------------------------------------------------------------------
// Pool allocation
// ----------------------------------------------------------------------------

// Allocates a component slot and returns a generational handle to it.
// Reclaimed slots are reused first; otherwise the bump pointer advances.
// Returns NULL_HANDLE when the pool is exhausted.
add_component :: proc(ctx: ^Context) -> Handle {
	index: u32

	if ctx.free_count > 0 {
		ctx.free_count -= 1
		index = ctx.free_slots[ctx.free_count]
	} else if ctx.next_empty_slot < MAX_COMPONENTS {
		index = ctx.next_empty_slot
		ctx.next_empty_slot += 1
	} else {
		return NULL_HANDLE
	}

	ctx.used[index] = true
	comp := &ctx.components[index]
	comp^ = {} // clear stale links/state from any previous occupant
	comp.active = true
	comp.visible = true

	return make_handle(index, ctx.generations[index])
}

// Makes a generational handle from a slot index and generation.
make_handle :: proc(index: u32, generation: u32) -> Handle {
	return Handle{index = index, generation = generation}
}

// Reports whether a handle still refers to a live component.
is_valid :: proc(ctx: ^Context, handle: Handle) -> bool {
	idx := handle.index
	if idx == 0 || idx >= MAX_COMPONENTS {
		return false
	}
	return bool(ctx.used[idx]) && ctx.generations[idx] == handle.generation
}

// Removes a component and its entire subtree, unlinking it from the tree
// and reclaiming the slots. The slot's generation is bumped so any existing
// handle to it becomes stale.
remove_component :: proc(ctx: ^Context, handle: Handle) {
	if !is_valid(ctx, handle) {
		return
	}

	// Recursively remove children first (grab next before freeing).
	child := get_component(ctx, handle).first_child
	for !handle_is_null(child) {
		next := get_component(ctx, child).next_sibling
		remove_component(ctx, child)
		child = next
	}

	unlink(ctx, handle)

	idx := handle.index
	ctx.used[idx] = false
	ctx.generations[idx] += 1
	ctx.free_slots[ctx.free_count] = idx
	ctx.free_count += 1
}

// Returns the component for a handle, or the null component (index 0) if the
// handle is stale or invalid. The null component is a safe write sink.
get_component :: proc(ctx: ^Context, handle: Handle) -> ^Component {
	if is_valid(ctx, handle) {
		return &ctx.components[handle.index]
	}
	return &ctx.components[0]
}

// ----------------------------------------------------------------------------
// Tree links (intrusive parent/child/sibling list)
// ----------------------------------------------------------------------------

get_parent :: proc(ctx: ^Context, handle: Handle) -> Handle {
	return get_component(ctx, handle).parent
}

get_first_child :: proc(ctx: ^Context, handle: Handle) -> Handle {
	return get_component(ctx, handle).first_child
}

get_last_child :: proc(ctx: ^Context, handle: Handle) -> Handle {
	return get_component(ctx, handle).last_child
}

get_next_sibling :: proc(ctx: ^Context, handle: Handle) -> Handle {
	return get_component(ctx, handle).next_sibling
}

get_prev_sibling :: proc(ctx: ^Context, handle: Handle) -> Handle {
	return get_component(ctx, handle).prev_sibling
}

// Detaches a node from its current parent's child list, repairing the
// neighbouring sibling links and the parent's first/last pointers.
// Safe to call on an already-detached node.
unlink :: proc(ctx: ^Context, handle: Handle) {
	if !is_valid(ctx, handle) {
		return
	}
	c := get_component(ctx, handle)

	if !handle_is_null(c.prev_sibling) {
		get_component(ctx, c.prev_sibling).next_sibling = c.next_sibling
	}
	if !handle_is_null(c.next_sibling) {
		get_component(ctx, c.next_sibling).prev_sibling = c.prev_sibling
	}
	if !handle_is_null(c.parent) {
		p := get_component(ctx, c.parent)
		if p.first_child == handle {
			p.first_child = c.next_sibling
		}
		if p.last_child == handle {
			p.last_child = c.prev_sibling
		}
	}

	c.parent = NULL_HANDLE
	c.prev_sibling = NULL_HANDLE
	c.next_sibling = NULL_HANDLE
}

// Re-parents `handle` under `parent`, appending it as the last child.
// Detaches from any previous parent first.
set_parent :: proc(ctx: ^Context, handle: Handle, parent: Handle) {
	if !is_valid(ctx, handle) || !is_valid(ctx, parent) {
		return
	}

	unlink(ctx, handle)

	c := get_component(ctx, handle)
	c.parent = parent

	p := get_component(ctx, parent)
	last := p.last_child
	if handle_is_null(last) {
		p.first_child = handle
		p.last_child = handle
		c.prev_sibling = NULL_HANDLE
		c.next_sibling = NULL_HANDLE
	} else {
		get_component(ctx, last).next_sibling = handle
		c.prev_sibling = last
		c.next_sibling = NULL_HANDLE
		p.last_child = handle
	}
}
