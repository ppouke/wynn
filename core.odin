package wynn

// ----------------------------------------------------------------------------
// Immediate-mode widgets
//
// Containers come in begin_*/end_* pairs (children emitted between them).
// Leaf widgets push one node and resolve interaction against the hot/active
// state set up in begin_frame. Interactive widgets take an explicit string id;
// stateful widgets take their value by pointer so the app owns the state.
// ----------------------------------------------------------------------------

DEFAULT_TEXT_SIZE :: f32(14)

WHITE :: vec4{1, 1, 1, 1}
BUTTON_COLOR :: vec4{0.20, 0.20, 0.22, 1}
CHECK_COLOR :: vec4{0.35, 0.35, 0.40, 1}
SLIDER_COLOR :: vec4{0.30, 0.30, 0.35, 1}
PANEL_COLOR :: vec4{0.15, 0.16, 0.20, 1}

// ---- Containers -----------------------------------------------------------

// A horizontal flow container (children left to right, `gap` between them).
begin_row :: proc(ctx: ^Context, gap: f32 = 0, padding := Sides{}, constraints := Constraints{}) {
	begin_container(ctx, Layout{kind = .Row, gap = {gap, 0}, padding = padding}, {}, constraints)
}
end_row :: proc(ctx: ^Context) {pop_container(ctx)}

// A vertical flow container (children top to bottom, `gap` between them).
begin_column :: proc(ctx: ^Context, gap: f32 = 0, padding := Sides{}, constraints := Constraints{}) {
	begin_container(ctx, Layout{kind = .Column, gap = {0, gap}, padding = padding}, {}, constraints)
}
end_column :: proc(ctx: ^Context) {pop_container(ctx)}

// A grid flow container with a fixed `columns` count; items wrap left to right.
begin_grid :: proc(
	ctx: ^Context,
	columns: i32,
	gap := vec2{0, 0},
	padding := Sides{},
	constraints := Constraints{},
) {
	begin_container(ctx, Layout{kind = .Grid, columns = columns, gap = gap, padding = padding}, {}, constraints)
}
end_grid :: proc(ctx: ^Context) {pop_container(ctx)}

// A colored panel. `layout` controls how its children are arranged (Column by
// default); size/position it via `constraints`.
begin_panel :: proc(
	ctx: ^Context,
	color := PANEL_COLOR,
	layout := Layout{kind = .Column},
	constraints := Constraints{},
) {
	begin_container(ctx, layout, color, constraints)
}
end_panel :: proc(ctx: ^Context) {pop_container(ctx)}

// Anchors the most recently emitted widget within its (None-layout) parent,
// overriding flow placement. Call immediately after the widget. Keeps the
// widget's size; sets which parent edges it pins to and the margins.
anchor :: proc(ctx: ^Context, edges: Anchor_Edges, margins := Sides{}) {
	if len(ctx.nodes) > 0 {
		ctx.nodes[len(ctx.nodes) - 1].constraints.anchors = edges
		ctx.nodes[len(ctx.nodes) - 1].constraints.margins = margins
	}
}

// ---- Leaf widgets ---------------------------------------------------------

// A text element (non-interactive). Sized by `size` (pref).
label :: proc(
	ctx: ^Context,
	text: string,
	text_size := DEFAULT_TEXT_SIZE,
	color := WHITE,
	size := vec2{0, 0},
) {
	idx := push_node(ctx)
	n := &ctx.nodes[idx]
	n.traits = {.Text}
	n.text = text
	n.text_size = text_size
	n.color = color
	n.constraints.pref_size = size
}

// A clickable, labelled box. Returns true on the frame it is clicked.
button :: proc(
	ctx: ^Context,
	id: string,
	text: string,
	size := vec2{96, 32},
	color := BUTTON_COLOR,
) -> bool {
	return button_id(ctx, get_id(id), text, size, color)
}

// Like `button` but takes a pre-computed ID (for derived/loop ids, e.g. menu
// items). Returns true on the frame it is clicked.
button_id :: proc(
	ctx: ^Context,
	id: ID,
	text: string,
	size := vec2{96, 32},
	color := BUTTON_COLOR,
) -> bool {
	idx := push_node(ctx)
	{
		n := &ctx.nodes[idx]
		n.id = id
		n.traits = {.Press, .Text}
		n.text = text
		n.text_size = DEFAULT_TEXT_SIZE
		n.color = color
		n.constraints.pref_size = size
	}
	return ctx.active == id && .Left in ctx.input.buttons_released && ctx.hot == id
}

// A boolean checkbox. Toggles `value` on click; returns true when it changed.
checkbox :: proc(
	ctx: ^Context,
	id: string,
	value: ^bool,
	size := vec2{22, 22},
	color := CHECK_COLOR,
) -> bool {
	wid := get_id(id)
	idx := push_node(ctx)
	{
		n := &ctx.nodes[idx]
		n.id = wid
		n.traits = {.Toggle}
		n.value = 1 if value^ else 0
		n.constraints.pref_size = size
		n.color = color
	}
	changed := false
	if ctx.active == wid && .Left in ctx.input.buttons_released && ctx.hot == wid {
		value^ = !value^
		ctx.nodes[idx].value = 1 if value^ else 0
		changed = true
	}
	return changed
}

// A boolean switch. Same behavior as checkbox; wider default size cues the
// switch look to the renderer.
toggle_switch :: proc(
	ctx: ^Context,
	id: string,
	value: ^bool,
	size := vec2{44, 22},
	color := CHECK_COLOR,
) -> bool {
	wid := get_id(id)
	idx := push_node(ctx)
	{
		n := &ctx.nodes[idx]
		n.id = wid
		n.traits = {.Toggle}
		n.value = 1 if value^ else 0
		n.constraints.pref_size = size
		n.color = color
	}
	changed := false
	if ctx.active == wid && .Left in ctx.input.buttons_released && ctx.hot == wid {
		value^ = !value^
		ctx.nodes[idx].value = 1 if value^ else 0
		changed = true
	}
	return changed
}

// A horizontal slider in [0,1]. Dragging sets `value`; returns true when it
// changed this frame.
slider :: proc(
	ctx: ^Context,
	id: string,
	value: ^f32,
	size := vec2{160, 20},
	color := SLIDER_COLOR,
) -> bool {
	wid := get_id(id)
	idx := push_node(ctx)
	{
		n := &ctx.nodes[idx]
		n.id = wid
		n.traits = {.Slide}
		n.constraints.pref_size = size
		n.color = color
	}
	changed := false
	if ctx.active == wid && .Left in ctx.input.buttons_down {
		if r, ok := prev_rect(ctx, wid); ok && r.size.x > 0 {
			t := clamp((ctx.input.mouse_pos.x - r.pos.x) / r.size.x, 0, 1)
			if t != value^ {
				value^ = t
				changed = true
			}
		}
	}
	ctx.nodes[idx].value = clamp(value^, 0, 1)
	return changed
}
