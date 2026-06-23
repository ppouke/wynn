package wynn

import "core:container/topological_sort"
import "core:mem"

MAX_COMPONENTS :: #config(WYNN_MAX_COMPONENTS, 1024)

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

// A Handle is a generational reference into the component pool.
// `index` is the slot in Context.components; `generation` must match the
// slot's current generation for the handle to be valid. The zero value
// (NULL_HANDLE) refers to the reserved null component at index 0.
Handle :: struct {
	index:      u32,
	generation: u32,
}

NULL_HANDLE :: Handle{}

handle_is_null :: proc(h: Handle) -> bool {
	return h == NULL_HANDLE
}

Traits :: distinct bit_set[Trait]
Trait :: enum {
	Move,
	Close,
	Hide,
	Resize,
	Text,
	Icon,
	Press,
	Toggle, // clicking flips `value` between 0 and 1 (checkbox/switch)
	Slide,  // dragging sets `value` in [0,1] from the cursor x (slider)
}

Component :: struct {
	//Intrusive list
	active:       bool,
	parent:       Handle,
	first_child:  Handle,
	next_sibling: Handle,
	prev_sibling: Handle,
	last_child:   Handle,
	traits:       Traits,
	constraints:  Constraints,
	layout:       Layout, // if kind != .None, flows this node's children
	rect:         Rect, // local rect, origin relative to parent
	global_rect:  Rect, // resolved absolute rect (filled by the arrange pass)
	color:        vec4,
	visible:      bool,
	text:         string,
	text_size:    f32,
	value:        f32, // normalized 0..1 (slider position / toggle on-off)
}

Render_Data :: struct {
	traits:    Traits,
	rect:      Rect, // resolved absolute rect
	color:     vec4,
	text:      string,
	text_size: f32,
	value:     f32,
}

// An axis-aligned rectangle: `pos` is the top-left origin, `size` is width/height.
Rect :: struct {
	pos:  vec2,
	size: vec2,
}

// Edges of a component that can be pinned to its parent.
Anchor_Edges :: distinct bit_set[Anchor_Edge]
Anchor_Edge :: enum {
	Left,
	Top,
	Right,
	Bottom,
}

// Distances from each parent edge, used by the anchored edges.
Sides :: struct {
	left:   f32,
	top:    f32,
	right:  f32,
	bottom: f32,
}

// Layout constraints for a component.
//
// `anchors` selects which edges are pinned to the parent; `margins` gives the
// distance from the corresponding parent edge for each pinned edge. Anchoring
// both edges of an axis (Left+Right or Top+Bottom) stretches the component on
// that axis; anchoring one edge fixes that side and the size comes from
// `pref_size` (clamped to min/max).
//
// `min_size`/`max_size`/`pref_size` are per-axis sizes in pixels.
// A `max_size` component of 0 means "unbounded" on that axis.
Constraints :: struct {
	anchors:   Anchor_Edges,
	margins:   Sides,
	min_size:  vec2,
	max_size:  vec2,
	pref_size: vec2,
}

// How a container arranges its direct children.
Layout_Kind :: enum {
	None,   // children positioned by their own anchors/constraints (default)
	Row,    // left to right
	Column, // top to bottom
	Grid,   // left to right, wrapping after `columns` items
}

// Container layout applied to a node's children. When `kind != .None`, the
// arrange pass positions the children by the flow and ignores their own
// anchors; each child keeps its measured size and a child may set its own
// `layout` to flow its grandchildren (containers nest).
//
// `gap` is the spacing between items (x = horizontal, y = vertical), `padding`
// insets the content area from the node's rect, and `columns` is the column
// count for Grid (clamped to >= 1).
Layout :: struct {
	kind:    Layout_Kind,
	gap:     vec2,
	padding: Sides,
	columns: i32,
}

Context :: struct {
	components:      [MAX_COMPONENTS]Component,
	used:            [MAX_COMPONENTS]b32,
	generations:     [MAX_COMPONENTS]u32, // current generation per slot
	free_slots:      [MAX_COMPONENTS]u32, // stack of reclaimed slot indices
	free_count:      i32,                 // number of entries in free_slots
	next_empty_slot: u32,                 // next never-used slot (bump pointer)
	screen:          Handle,              //top of tree
	input:           Input,
	hovered:         Handle,              // component under the mouse this frame
	active:          Handle,              // component capturing the press (mouse held)
	focused:         Handle,              // component focused by the last press
	clicked:         Handle,              // component clicked this frame (press+release on it)
}

//Initializes the framework.
initialize :: proc(allocator: mem.Allocator, screen_size: vec2) -> ^Context {
	ctx := new(Context, allocator)
	ctx.next_empty_slot = 1 // slot 0 is the reserved null component

	ctx.screen = add_component(ctx)
	update_screen_size(ctx, screen_size)

	return ctx
}

process_ui :: proc(ctx: ^Context) {
	solve_layout(ctx)
}

update_screen_size :: proc(ctx: ^Context, screen_size: vec2) {
	screen_comp := get_component(ctx, ctx.screen)
	screen_comp.rect = Rect{pos = {0.0, 0.0}, size = screen_size}
	screen_comp.global_rect = screen_comp.rect
}
