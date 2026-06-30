package wynn_test

import "core:testing"
import wynn ".."
import cl "../components_library"

Box_State :: struct {
	clicked: bool,
}

// A button "box" pinned at {100,100} size {100,100} (center {150,150}).
build_box :: proc(ctx: ^wynn.Context, st: ^Box_State) {
	st.clicked = wynn.button(ctx, "box", "B", {100, 100})
	wynn.anchor(ctx, {.Left, .Top}, {left = 100, top = 100})
}

@(test)
test_hover :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Box_State
	boxid := wynn.get_id("box")

	frame(ctx, build_box, &st) // establish geometry

	wynn.input_mouse_move(ctx, {150, 150})
	frame(ctx, build_box, &st)
	testing.expect(t, wynn.is_hot(ctx, boxid))

	wynn.input_mouse_move(ctx, {10, 10})
	frame(ctx, build_box, &st)
	testing.expect(t, !wynn.is_hot(ctx, boxid))
}

@(test)
test_click_press_release_same :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Box_State
	boxid := wynn.get_id("box")

	frame(ctx, build_box, &st) // geometry

	press_frame(ctx, {150, 150}, build_box, &st)
	testing.expect(t, wynn.is_active(ctx, boxid))
	testing.expect(t, !st.clicked) // still held, no click yet

	release_frame(ctx, build_box, &st)
	testing.expect(t, st.clicked)
	testing.expect(t, !wynn.is_active(ctx, boxid)) // capture released
}

@(test)
test_no_click_when_release_elsewhere :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st: Box_State

	frame(ctx, build_box, &st) // geometry
	press_frame(ctx, {150, 150}, build_box, &st)

	// move off the box, then release -> hover is elsewhere, so no click
	wynn.input_mouse_move(ctx, {10, 10})
	wynn.input_mouse_button_up(ctx, .Left)
	frame(ctx, build_box, &st)

	testing.expect(t, !st.clicked)
}

Drag_State :: struct {
	pos: wynn.vec2,
}

// A floating window (overlay) whose body drag updates st.pos via the Move trait.
build_win :: proc(ctx: ^wynn.Context, st: ^Drag_State) {
	cl.begin_floating(ctx, "win", &st.pos, {100, 100}, layout = wynn.Layout{})
	cl.end_floating(ctx)
}

@(test)
test_drag_moves_floating_window :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Drag_State{pos = {100, 100}} // body covers {100,100 .. 200,200}

	frame(ctx, build_win, &st) // geometry

	// position the cursor over the body (so the next press captures it), letting
	// end_frame clear the motion delta before the drag begins
	wynn.input_mouse_move(ctx, {150, 150})
	frame(ctx, build_win, &st)

	// press: captures the window, but with zero delta so it does not move yet
	wynn.input_mouse_button_down(ctx, .Left)
	frame(ctx, build_win, &st)
	testing.expect_value(t, st.pos, wynn.vec2{100, 100})

	// drag by (10, 20) while held
	wynn.input_mouse_move(ctx, {160, 170})
	frame(ctx, build_win, &st)
	testing.expect_value(t, st.pos, wynn.vec2{110, 120})
}
