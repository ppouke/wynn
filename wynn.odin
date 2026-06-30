package wynn

import "core:mem"

// ----------------------------------------------------------------------------
// wynn — immediate-mode UI core
//
// Each frame the app calls begin_frame, emits widgets (which build a transient
// tree of Nodes in a per-frame arena), then end_frame (solves layout) and
// render (emits draw data). Nothing is retained between frames except a little
// interaction state keyed by explicit IDs. See DESIGN.md.
// ----------------------------------------------------------------------------

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

// Frame-local node link sentinel ("no node").
NO_NODE :: -1

// Stable identity for an interactive widget, hashed from the caller's explicit
// string id. 0 means "non-interactive" (the default).
ID :: distinct u64

// Opaque reference to a host-owned image/texture. The library never touches the
// pixels; it only forwards this handle to the renderer, which maps it to its own
// texture. 0 means "no image". The host decides what the bits mean (e.g. a GL
// texture name, or an index into a host-side image table).
Image_Handle :: distinct u32

Traits :: distinct bit_set[Trait]
Trait :: enum {
	Move,
	Close,
	Hide,
	Resize,
	Text,
	Icon,
	Press,
	Toggle, // value flips 0/1 (checkbox/switch)
	Slide,  // value set from cursor (slider)
}

// An axis-aligned rectangle: `pos` is the top-left origin, `size` is width/height.
Rect :: struct {
	pos:  vec2,
	size: vec2,
}

// Edges of a node that can be pinned to its parent.
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

// Layout constraints for a node. Anchoring both edges of an axis stretches it;
// one edge fixes that side with size from `pref_size` (clamped to min/max).
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

Layout :: struct {
	kind:    Layout_Kind,
	gap:     vec2,
	padding: Sides,
	columns: i32,
}

// A transient per-frame node. Links are frame-local indices into Context.nodes
// (NO_NODE = none). Rebuilt every frame; not addressed by stable handles.
Node :: struct {
	parent:       int,
	first_child:  int,
	last_child:   int,
	next_sibling: int,
	constraints:  Constraints,
	layout:       Layout,
	rect:         Rect, // local placement (explicit/unanchored)
	global_rect:  Rect, // resolved by the solver
	traits:       Traits,
	color:        vec4,
	text:         string,
	text_size:    f32,
	value:        f32,
	image:        Image_Handle, // 0 = none; host-owned texture for .Icon nodes
	id:           ID,  // 0 = non-interactive
	layer:        int, // 0 = normal; higher = overlay (drawn/hit above lower)
}

// Outcome of an interactive control, filled according to its traits:
//   .Press  → hovered / held / clicked
//   .Toggle → flips the bound bool, sets changed
//   .Slide  → sets the bound f32 from the cursor, sets changed
// Fields for traits the control does not have stay false.
Interaction :: struct {
	hovered: bool,
	held:    bool,
	clicked: bool,
	changed: bool,
}

// Flat draw record emitted by `render`, consumed by the host's renderer.
Render_Data :: struct {
	traits:    Traits,
	rect:      Rect,
	color:     vec4,
	text:      string,
	text_size: f32,
	value:     f32,
	image:     Image_Handle,
}

Context :: struct {
	nodes:       [dynamic]Node, // current frame, built between begin/end_frame
	prev_nodes:  [dynamic]Node, // last frame, solved — used for hit-testing
	stack:       [dynamic]int,  // open container indices (top = current parent)
	screen_size: vec2,
	input:       Input,
	hot:         ID,  // hovered id, resolved from last frame's geometry
	hot_node:    int, // topmost hit node index in prev frame (for mouse_over_ui)
	active:      ID,  // mouse-captured id (set on press, held until release)
	focused:     ID,  // focused id (set on press)
	allocator:   mem.Allocator,
}

// Allocates a context. Free it with `destroy`.
initialize :: proc(allocator: mem.Allocator, screen_size: vec2) -> ^Context {
	ctx := new(Context, allocator)
	ctx.allocator = allocator
	ctx.nodes = make([dynamic]Node, allocator)
	ctx.prev_nodes = make([dynamic]Node, allocator)
	ctx.stack = make([dynamic]int, allocator)
	ctx.screen_size = screen_size
	ctx.hot_node = NO_NODE
	return ctx
}

destroy :: proc(ctx: ^Context) {
	delete(ctx.nodes)
	delete(ctx.prev_nodes)
	delete(ctx.stack)
	free(ctx, ctx.allocator)
}

update_screen_size :: proc(ctx: ^Context, screen_size: vec2) {
	ctx.screen_size = screen_size
}

// FNV-1a hash of an explicit widget id. The caller guarantees uniqueness.
get_id :: proc(s: string) -> ID {
	h: u64 = 0xcbf29ce484222325
	for i in 0 ..< len(s) {
		h = (h ~ u64(s[i])) * 0x100000001b3
	}
	return ID(h)
}

// ----------------------------------------------------------------------------
// Frame lifecycle
// ----------------------------------------------------------------------------

// Starts a frame: recycles the arena, pushes the screen root, resolves hover
// from last frame's geometry, and captures the press target.
begin_frame :: proc(ctx: ^Context, screen_size: vec2) {
	ctx.screen_size = screen_size

	// Last frame's nodes become the geometry we hit-test against.
	ctx.prev_nodes, ctx.nodes = ctx.nodes, ctx.prev_nodes
	clear(&ctx.nodes)
	clear(&ctx.stack)

	root := push_node(ctx) // index 0, no parent (stack is empty)
	ctx.nodes[root].rect = Rect{{0, 0}, screen_size}
	ctx.nodes[root].global_rect = ctx.nodes[root].rect
	append(&ctx.stack, root)

	update_hot(ctx)

	// Capture the press target so widgets can resolve clicks/drags this frame.
	if ctx.hot != 0 && .Left in ctx.input.buttons_pressed {
		ctx.active = ctx.hot
		ctx.focused = ctx.hot
	}
}

// Ends a frame: solves layout, releases capture on mouse-up, and consumes the
// per-frame input edges. Call `render` afterwards to emit draw data.
end_frame :: proc(ctx: ^Context) {
	solve_layout(ctx)

	if .Left not_in ctx.input.buttons_down {
		ctx.active = 0
	}

	inp := &ctx.input
	inp.buttons_pressed = {}
	inp.buttons_released = {}
	inp.keys_pressed = {}
	inp.mouse_delta = {}
	inp.scroll_delta = {}
}

// ----------------------------------------------------------------------------
// Transient tree construction
// ----------------------------------------------------------------------------

// Appends a fresh node, links it under the current container (stack top), and
// returns its index. Callers set fields by index afterwards (do not hold a
// node pointer across further pushes — the arena may reallocate).
push_node :: proc(ctx: ^Context) -> int {
	idx := len(ctx.nodes)
	append(
		&ctx.nodes,
		Node{parent = NO_NODE, first_child = NO_NODE, last_child = NO_NODE, next_sibling = NO_NODE},
	)
	layer := 0
	if len(ctx.stack) > 0 {
		parent := ctx.stack[len(ctx.stack) - 1]
		layer = ctx.nodes[parent].layer
		link_child(ctx, parent, idx)
	}
	ctx.nodes[idx].layer = layer
	return idx
}

@(private = "file")
link_child :: proc(ctx: ^Context, parent, child: int) {
	ctx.nodes[child].parent = parent
	if ctx.nodes[parent].first_child == NO_NODE {
		ctx.nodes[parent].first_child = child
		ctx.nodes[parent].last_child = child
	} else {
		ctx.nodes[ctx.nodes[parent].last_child].next_sibling = child
		ctx.nodes[parent].last_child = child
	}
}

// Opens a container node (pushed onto the stack). Pair with pop_container.
begin_container :: proc(ctx: ^Context, layout: Layout, color := vec4{}, constraints := Constraints{}) -> int {
	idx := push_node(ctx)
	ctx.nodes[idx].layout = layout
	ctx.nodes[idx].color = color
	ctx.nodes[idx].constraints = constraints
	append(&ctx.stack, idx)
	return idx
}

// Closes the current container. Never pops the root.
pop_container :: proc(ctx: ^Context) {
	if len(ctx.stack) > 1 {
		pop(&ctx.stack)
	}
}

// Opens a container parented to the screen root on the overlay layer, placed
// absolutely at `pos`. Used for floating windows and menu dropdowns so they
// draw above and hit-test before normal content regardless of call order.
// Pair with end_overlay (alias of pop_container).
begin_overlay :: proc(ctx: ^Context, pos: vec2, size: vec2, color := vec4{}, layout := Layout{}) -> int {
	idx := len(ctx.nodes)
	append(
		&ctx.nodes,
		Node{parent = NO_NODE, first_child = NO_NODE, last_child = NO_NODE, next_sibling = NO_NODE},
	)
	link_child(ctx, 0, idx) // parent to the screen root, not the current container
	ctx.nodes[idx].layer = 1
	ctx.nodes[idx].rect.pos = pos
	ctx.nodes[idx].constraints.pref_size = size
	ctx.nodes[idx].color = color
	ctx.nodes[idx].layout = layout
	append(&ctx.stack, idx)
	return idx
}

end_overlay :: proc(ctx: ^Context) {pop_container(ctx)}

// Looks up a node's resolved rect from the previous (solved) frame by id.
prev_rect :: proc(ctx: ^Context, id: ID) -> (Rect, bool) {
	for n in ctx.prev_nodes {
		if n.id == id {
			return n.global_rect, true
		}
	}
	return {}, false
}
