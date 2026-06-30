package wynn_test

import "core:testing"
import wynn ".."

// Immediate mode has no `visible` flag: a node is "hidden" simply by not
// emitting it that frame. These tests cover that emission semantics plus the
// mouse_over_ui query (both resolve against the previous frame's geometry).

Vis_State :: struct {
	emit: bool,
}

// A button "ok" at the origin, size {100,30}, emitted only when st.emit.
build_toggle_btn :: proc(ctx: ^wynn.Context, st: ^Vis_State) {
	if st.emit {
		wynn.button(ctx, "ok", "OK", {100, 30})
		wynn.anchor(ctx, {.Left, .Top})
	}
}

@(test)
test_mouse_over_ui :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Vis_State{emit = true}

	frame(ctx, build_toggle_btn, &st) // geometry; button at {0,0 .. 100,30}

	// over the button -> true
	wynn.input_mouse_move(ctx, {20, 15})
	frame(ctx, build_toggle_btn, &st)
	testing.expect(t, wynn.mouse_over_ui(ctx))

	// over empty background -> false
	wynn.input_mouse_move(ctx, {400, 400})
	frame(ctx, build_toggle_btn, &st)
	testing.expect(t, !wynn.mouse_over_ui(ctx))

	// outside the window entirely -> false
	wynn.input_mouse_move(ctx, {-5, -5})
	frame(ctx, build_toggle_btn, &st)
	testing.expect(t, !wynn.mouse_over_ui(ctx))

	// stop emitting the button: once it leaves the previous frame, the cursor is
	// over the background again. One frame to drop it from geometry, one to read.
	st.emit = false
	wynn.input_mouse_move(ctx, {20, 15})
	frame(ctx, build_toggle_btn, &st)
	frame(ctx, build_toggle_btn, &st)
	testing.expect(t, !wynn.mouse_over_ui(ctx))
}

@(test)
test_unemitted_node_not_hit :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Vis_State{emit = true}

	// two frames so prev_nodes holds the emitted button (index 1)
	frame(ctx, build_toggle_btn, &st)
	frame(ctx, build_toggle_btn, &st)
	testing.expect_value(t, wynn.hit_test(ctx, {20, 15}), 1)

	// stop emitting it; after it clears from prev_nodes the point falls through
	st.emit = false
	frame(ctx, build_toggle_btn, &st)
	frame(ctx, build_toggle_btn, &st)
	testing.expect_value(t, wynn.hit_test(ctx, {20, 15}), wynn.NO_NODE)
}
