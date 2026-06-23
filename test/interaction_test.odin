package wynn_test

import "core:testing"
import wynn ".."

// Component occupying {100,100 .. 200,200} on screen.
box :: proc(ctx: ^wynn.Context, traits: wynn.Traits = {}) -> wynn.Handle {
	h := make(ctx, ctx.screen, wynn.Constraints{pref_size = {100, 100}})
	c := wynn.get_component(ctx, h)
	c.rect.pos = {100, 100}
	c.traits = traits
	wynn.process_ui(ctx)
	return h
}

@(test)
test_hover :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	h := box(ctx)

	wynn.input_mouse_move(ctx, {150, 150})
	wynn.process_input(ctx)
	testing.expect(t, wynn.is_hovered(ctx, h))

	wynn.input_mouse_move(ctx, {10, 10})
	wynn.process_input(ctx)
	testing.expect(t, !wynn.is_hovered(ctx, h))
}

@(test)
test_click_press_release_same :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	h := box(ctx)

	wynn.input_mouse_move(ctx, {150, 150})
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)
	testing.expect(t, wynn.is_active(ctx, h))
	testing.expect(t, wynn.is_focused(ctx, h))
	testing.expect(t, !wynn.was_clicked(ctx, h)) // not yet, still held

	wynn.input_mouse_button_up(ctx, .Left)
	wynn.process_input(ctx)
	testing.expect(t, wynn.was_clicked(ctx, h))
	testing.expect(t, !wynn.is_active(ctx, h)) // capture released
}

@(test)
test_no_click_when_release_elsewhere :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	h := box(ctx)

	wynn.input_mouse_move(ctx, {150, 150})
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)

	// move off the component, then release
	wynn.input_mouse_move(ctx, {10, 10})
	wynn.input_mouse_button_up(ctx, .Left)
	wynn.process_input(ctx)

	testing.expect(t, !wynn.was_clicked(ctx, h))
	testing.expect_value(t, ctx.clicked, wynn.NULL_HANDLE)
}

@(test)
test_drag_moves_component_with_move_trait :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	h := box(ctx, {.Move})

	// establish position, then press
	wynn.input_mouse_move(ctx, {150, 150})
	wynn.process_input(ctx)
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)

	// drag by (10, 20) while held
	wynn.input_mouse_move(ctx, {160, 170})
	wynn.process_input(ctx)

	testing.expect_value(t, wynn.get_component(ctx, h).rect.pos, wynn.vec2{110, 120})
}

@(test)
test_drag_ignored_without_move_trait :: proc(t: ^testing.T) {
	ctx := wynn.initialize(context.allocator, {800, 600})
	defer free(ctx)
	h := box(ctx) // no traits

	wynn.input_mouse_move(ctx, {150, 150})
	wynn.process_input(ctx)
	wynn.input_mouse_button_down(ctx, .Left)
	wynn.process_input(ctx)

	wynn.input_mouse_move(ctx, {160, 170})
	wynn.process_input(ctx)

	testing.expect_value(t, wynn.get_component(ctx, h).rect.pos, wynn.vec2{100, 100})
}
