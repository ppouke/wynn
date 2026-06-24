package wynn

// ----------------------------------------------------------------------------
// Base widgets
//
// Thin convenience constructors over the low-level API (add_component +
// set_parent + Component fields). Each returns the new component's Handle, so
// callers keep the handle to query interaction (e.g. was_clicked) or to tweak
// fields afterwards via get_component.
//
// Larger composite widgets (toolbar, menus, ...) live in the separate
// `components_library` package, which is built on top of these.
// ----------------------------------------------------------------------------

DEFAULT_TEXT_SIZE :: f32(14)

WHITE :: vec4{1, 1, 1, 1}
BUTTON_COLOR :: vec4{0.20, 0.20, 0.22, 1}
CHECK_COLOR :: vec4{0.35, 0.35, 0.40, 1}
SLIDER_COLOR :: vec4{0.30, 0.30, 0.35, 1}

// Creates a component parented under `parent` and returns its handle.
new_child :: proc(ctx: ^Context, parent: Handle) -> Handle {
	h := add_component(ctx)
	set_parent(ctx, h, parent)
	return h
}

// A text element. Sized by `size` (pref); the host renders `text` at
// `text_size` using the Text trait.
label :: proc(
	ctx: ^Context,
	parent: Handle,
	text: string,
	text_size := DEFAULT_TEXT_SIZE,
	color := WHITE,
	size := vec2{0, 0},
) -> Handle {
	h := new_child(ctx, parent)
	c := get_component(ctx, h)
	c.traits += {.Text}
	c.text = text
	c.text_size = text_size
	c.color = color
	c.constraints.pref_size = size
	return h
}

// A clickable, labelled box. Poll `was_clicked(ctx, h)` after process_input.
button :: proc(
	ctx: ^Context,
	parent: Handle,
	text: string,
	size := vec2{96, 32},
	color := BUTTON_COLOR,
) -> Handle {
	h := new_child(ctx, parent)
	c := get_component(ctx, h)
	c.traits += {.Press, .Text}
	c.text = text
	c.text_size = DEFAULT_TEXT_SIZE
	c.color = color
	c.constraints.pref_size = size
	return h
}

// A boolean checkbox. Toggles `value` (0/1) on click; read it back via
// get_component(ctx, h).value (>= 0.5 means checked).
checkbox :: proc(
	ctx: ^Context,
	parent: Handle,
	checked := false,
	size := vec2{22, 22},
	color := CHECK_COLOR,
) -> Handle {
	h := new_child(ctx, parent)
	c := get_component(ctx, h)
	c.traits += {.Toggle}
	c.value = 1 if checked else 0
	c.constraints.pref_size = size
	c.color = color
	return h
}

// A boolean switch. Identical behavior to `checkbox` (a Toggle); a wider
// default size signals the switch look to the renderer.
toggle_switch :: proc(
	ctx: ^Context,
	parent: Handle,
	on := false,
	size := vec2{44, 22},
	color := CHECK_COLOR,
) -> Handle {
	h := new_child(ctx, parent)
	c := get_component(ctx, h)
	c.traits += {.Toggle}
	c.value = 1 if on else 0
	c.constraints.pref_size = size
	c.color = color
	return h
}

// A horizontal slider. Dragging sets `value` in [0,1]; starts at `value`
// (clamped). Read it back via get_component(ctx, h).value.
slider :: proc(
	ctx: ^Context,
	parent: Handle,
	value := f32(0),
	size := vec2{160, 20},
	color := SLIDER_COLOR,
) -> Handle {
	h := new_child(ctx, parent)
	c := get_component(ctx, h)
	c.traits += {.Slide}
	c.value = clamp(value, 0, 1)
	c.constraints.pref_size = size
	c.color = color
	return h
}

// A horizontal flow container. Children added under the returned handle are
// laid out left to right with `gap` between them. Size it via its constraints.
row :: proc(ctx: ^Context, parent: Handle, gap: f32 = 0, padding := Sides{}) -> Handle {
	h := new_child(ctx, parent)
	get_component(ctx, h).layout = Layout {
		kind    = .Row,
		gap     = {gap, 0},
		padding = padding,
	}
	return h
}

// A vertical flow container (top to bottom, `gap` between items).
column :: proc(ctx: ^Context, parent: Handle, gap: f32 = 0, padding := Sides{}) -> Handle {
	h := new_child(ctx, parent)
	get_component(ctx, h).layout = Layout {
		kind    = .Column,
		gap     = {0, gap},
		padding = padding,
	}
	return h
}

// A grid flow container with a fixed `columns` count; items wrap left to right.
grid :: proc(
	ctx: ^Context,
	parent: Handle,
	columns: i32,
	gap := vec2{0, 0},
	padding := Sides{},
) -> Handle {
	h := new_child(ctx, parent)
	get_component(ctx, h).layout = Layout {
		kind    = .Grid,
		columns = columns,
		gap     = gap,
		padding = padding,
	}
	return h
}
