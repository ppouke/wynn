package wynn

Mouse_Buttons :: distinct bit_set[Mouse_Button]
Mouse_Button :: enum {
	Left,
	Middle,
	Right,
}

Keys :: distinct bit_set[Key]
Key :: enum {
	Space,
	LShift,
	RShift,
	Return,
	Backspace,
	Alt,
	Esc,
	Ctrl,
}

// Fed by the host between frames via the input_* procs and consumed by
// begin_frame/end_frame. `*_down` are held sets; `*_pressed`/`*_released` are
// this-frame edges accumulated from events (so a press+release within one frame
// is still seen). end_frame clears the per-frame fields.
Input :: struct {
	mouse_pos:        vec2,
	mouse_delta:      vec2,
	scroll_delta:     vec2,
	buttons_down:     Mouse_Buttons,
	buttons_pressed:  Mouse_Buttons,
	buttons_released: Mouse_Buttons,
	keys_down:        Keys,
	keys_pressed:     Keys,
}

// ----------------------------------------------------------------------------
// Host-facing event feed
// ----------------------------------------------------------------------------

input_mouse_move :: proc(ctx: ^Context, pos: vec2) {
	ctx.input.mouse_delta += pos - ctx.input.mouse_pos
	ctx.input.mouse_pos = pos
}

input_mouse_scroll :: proc(ctx: ^Context, delta: vec2) {
	ctx.input.scroll_delta += delta
}

input_mouse_button_down :: proc(ctx: ^Context, btn: Mouse_Button) {
	ctx.input.buttons_down += {btn}
	ctx.input.buttons_pressed += {btn}
}

input_mouse_buttons_down :: proc(ctx: ^Context, btns: Mouse_Buttons) {
	ctx.input.buttons_down += btns
	ctx.input.buttons_pressed += btns
}

input_mouse_button_up :: proc(ctx: ^Context, btn: Mouse_Button) {
	ctx.input.buttons_down -= {btn}
	ctx.input.buttons_released += {btn}
}

input_mouse_buttons_up :: proc(ctx: ^Context, btns: Mouse_Buttons) {
	ctx.input.buttons_down -= btns
	ctx.input.buttons_released += btns
}

input_key_down :: proc(ctx: ^Context, key: Key) {
	ctx.input.keys_down += {key}
	ctx.input.keys_pressed += {key}
}

input_keys_down :: proc(ctx: ^Context, keys: Keys) {
	ctx.input.keys_down += keys
	ctx.input.keys_pressed += keys
}

input_key_up :: proc(ctx: ^Context, key: Key) {
	ctx.input.keys_down -= {key}
}

input_keys_up :: proc(ctx: ^Context, keys: Keys) {
	ctx.input.keys_down -= keys
}

// ----------------------------------------------------------------------------
// Hover resolution + queries
// ----------------------------------------------------------------------------

// Resolves the hovered node from the previous (solved) frame's geometry. Called
// by begin_frame. Sets ctx.hot_node (topmost node index) and ctx.hot (its id).
update_hot :: proc(ctx: ^Context) {
	idx := hit_test(ctx, ctx.input.mouse_pos)
	ctx.hot_node = idx
	ctx.hot = idx != NO_NODE ? ctx.prev_nodes[idx].id : 0
}

// Topmost previous-frame node under `point`, or NO_NODE if only the background.
// Front-most = highest layer, then highest array index (painter order). Index 0
// (screen root) is the background and never returned.
hit_test :: proc(ctx: ^Context, point: vec2) -> int {
	result := NO_NODE
	best_layer := -1
	for i in 1 ..< len(ctx.prev_nodes) {
		n := ctx.prev_nodes[i]
		if n.layer >= best_layer && rect_contains(n.global_rect, point) {
			result = i
			best_layer = n.layer
		}
	}
	return result
}

is_hot :: proc(ctx: ^Context, id: ID) -> bool {
	return id != 0 && ctx.hot == id
}

is_active :: proc(ctx: ^Context, id: ID) -> bool {
	return id != 0 && ctx.active == id
}

is_focused :: proc(ctx: ^Context, id: ID) -> bool {
	return id != 0 && ctx.focused == id
}

// Reports whether the mouse is over a UI element (any node but the background).
mouse_over_ui :: proc(ctx: ^Context) -> bool {
	return ctx.hot_node != NO_NODE && ctx.hot_node != 0
}
