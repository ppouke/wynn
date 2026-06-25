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

// Input is fed by the host between frames via the input_* procs, then consumed
// once per frame by process_input. `*_down` are the currently-held sets;
// `*_pressed`/`*_released` are this-frame edges accumulated from events (so a
// press+release inside one frame is still seen). `mouse_delta`/`scroll_delta`
// accumulate motion since the last process_input. process_input clears all the
// per-frame fields after consuming them.
Input :: struct {
	mouse_pos:        vec2,
	mouse_delta:      vec2, // accumulated motion since last process_input
	scroll_delta:     vec2, // accumulated scroll since last process_input
	buttons_down:     Mouse_Buttons, // currently held
	buttons_pressed:  Mouse_Buttons, // went down this frame
	buttons_released: Mouse_Buttons, // went up this frame
	keys_down:        Keys, // currently held
	keys_pressed:     Keys, // went down this frame
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
// Per-frame interaction resolution
//
// Call once per frame, before process_ui, so any drag updates land in the
// layout solve. Resolves, for the primary (Left) button:
//   - hovered:  the top-most component under the cursor (last frame's layout)
//   - active:   the component that captured the press; held until release
//   - focused:  set to the active component on press
//   - clicked:  set when the press and release land on the same component
// Components with the Move trait are dragged by the mouse delta while active.
// Close/Hide/Press semantics are left to the host: poll is_hovered/is_active/
// is_focused/was_clicked and act on the component's traits as the app sees fit.
// ----------------------------------------------------------------------------

process_input :: proc(ctx: ^Context) {
	inp := &ctx.input

	ctx.hovered = hit_test(ctx, inp.mouse_pos)
	ctx.clicked = NULL_HANDLE

	if .Left in inp.buttons_pressed {
		ctx.active = ctx.hovered
		ctx.focused = ctx.hovered
	}

	// Drive the captured component's spatial/value behavior while held.
	if .Left in inp.buttons_down && is_valid(ctx, ctx.active) {
		a := get_component(ctx, ctx.active)
		if .Move in a.traits {
			a.rect.pos += inp.mouse_delta
		}
		if .Slide in a.traits && a.global_rect.size.x > 0 {
			t := (inp.mouse_pos.x - a.global_rect.pos.x) / a.global_rect.size.x
			a.value = clamp(t, 0, 1)
		}
	}

	if .Left in inp.buttons_released {
		if is_valid(ctx, ctx.active) && ctx.active == ctx.hovered {
			ctx.clicked = ctx.active
			c := get_component(ctx, ctx.clicked)
			if .Toggle in c.traits {
				c.value = 0 if c.value >= 0.5 else 1
			}
		}
		ctx.active = NULL_HANDLE
	}

	// Consume this frame's edges/motion.
	inp.buttons_pressed = {}
	inp.buttons_released = {}
	inp.keys_pressed = {}
	inp.mouse_delta = {}
	inp.scroll_delta = {}
}

// ----------------------------------------------------------------------------
// Interaction queries (host polls these after process_input)
// ----------------------------------------------------------------------------

is_hovered :: proc(ctx: ^Context, h: Handle) -> bool {
	return !handle_is_null(h) && ctx.hovered == h
}

is_active :: proc(ctx: ^Context, h: Handle) -> bool {
	return !handle_is_null(h) && ctx.active == h
}

is_focused :: proc(ctx: ^Context, h: Handle) -> bool {
	return !handle_is_null(h) && ctx.focused == h
}

was_clicked :: proc(ctx: ^Context, h: Handle) -> bool {
	return !handle_is_null(h) && ctx.clicked == h
}

// Reports whether the mouse is currently over a visible UI component, i.e. any
// hovered component other than the screen background (empty space resolves to
// the screen root). Uses the hover resolved by the last process_input; hit-
// testing already skips hidden subtrees, so a component hidden via itself or an
// ancestor does not count. Handy for deciding whether the UI should consume the
// mouse this frame rather than passing it to the world behind it.
mouse_over_ui :: proc(ctx: ^Context) -> bool {
	return !handle_is_null(ctx.hovered) && ctx.hovered != ctx.screen
}

// Returns the top-most visible component containing `point`, or NULL_HANDLE if
// none (not even the screen) contains it. Children are tested in reverse draw
// order so the front-most node wins, and the deepest hit is returned.
// A node only descends into its children if `point` is inside its own rect,
// which assumes children are visually clipped to their parent.
hit_test :: proc(ctx: ^Context, point: vec2) -> Handle {
	return hit_node(ctx, ctx.screen, point)
}

@(private = "file")
hit_node :: proc(ctx: ^Context, handle: Handle, point: vec2) -> Handle {
	c := get_component(ctx, handle)
	if !c.visible || !rect_contains(c.global_rect, point) {
		return NULL_HANDLE
	}

	// Last child draws on top, so test from last to first.
	child := c.last_child
	for !handle_is_null(child) {
		hit := hit_node(ctx, child, point)
		if !handle_is_null(hit) {
			return hit
		}
		child = get_component(ctx, child).prev_sibling
	}

	return handle
}
