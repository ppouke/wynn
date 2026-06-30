package wynn_test

import "core:testing"
import wynn ".."

// Stateful widgets own no state in wynn: the app passes a pointer and the widget
// mutates it. Tests assert against that caller-owned value.

Bool_State :: struct {
	v: bool,
}

// A checkbox "cb" pinned at {10,10} size {20,20} (center {20,20}).
build_checkbox :: proc(ctx: ^wynn.Context, st: ^Bool_State) {
	wynn.checkbox(ctx, "cb", &st.v, {20, 20})
	wynn.anchor(ctx, {.Left, .Top}, {left = 10, top = 10})
}

@(test)
test_checkbox_toggles :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Bool_State{v = false}

	frame(ctx, build_checkbox, &st) // geometry

	click(ctx, {20, 20}, build_checkbox, &st)
	testing.expect(t, st.v) // now checked

	click(ctx, {20, 20}, build_checkbox, &st)
	testing.expect(t, !st.v) // back off
}

// A switch "sw" pinned at the origin, size {44,22} (center {22,11}).
build_switch :: proc(ctx: ^wynn.Context, st: ^Bool_State) {
	wynn.toggle_switch(ctx, "sw", &st.v, {44, 22})
	wynn.anchor(ctx, {.Left, .Top})
}

@(test)
test_switch_toggles :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Bool_State{v = true}

	frame(ctx, build_switch, &st) // geometry

	click(ctx, {22, 11}, build_switch, &st)
	testing.expect(t, !st.v)
}

Slider_State :: struct {
	val: f32,
}

// A slider "s" pinned at {100,50} size {200,20} (track spans x in [100,300]).
build_slider :: proc(ctx: ^wynn.Context, st: ^Slider_State) {
	wynn.slider(ctx, "s", &st.val, {200, 20})
	wynn.anchor(ctx, {.Left, .Top}, {left = 100, top = 50})
}

@(test)
test_slider_sets_value_from_cursor :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Slider_State{val = 0}

	frame(ctx, build_slider, &st) // geometry; track spans x in [100, 300]

	// press at the middle of the track -> value ~0.5
	press_frame(ctx, {200, 60}, build_slider, &st)
	testing.expect_value(t, st.val, f32(0.5))

	// drag to the far right -> clamped to 1 (still held)
	wynn.input_mouse_move(ctx, {400, 60})
	frame(ctx, build_slider, &st)
	testing.expect_value(t, st.val, f32(1))

	// release; moving while not held does nothing
	wynn.input_mouse_button_up(ctx, .Left)
	wynn.input_mouse_move(ctx, {0, 60})
	frame(ctx, build_slider, &st)
	testing.expect_value(t, st.val, f32(1)) // unchanged after release
}

@(test)
test_slider_emits_value :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, SCREEN)
	defer wynn.destroy(ctx)
	st := Slider_State{val = 0.25}

	frame(ctx, build_slider, &st)

	data := wynn.render(ctx, context.allocator)
	defer delete(data, context.allocator)

	testing.expect_value(t, len(data), 1)
	testing.expect_value(t, data[0].value, f32(0.25))
	testing.expect(t, .Slide in data[0].traits)
}
