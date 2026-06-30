package wynn_test

import wynn ".."

// Shared test scaffolding for the immediate-mode core.
//
// Immediate mode rebuilds the whole UI every frame, so tests that exercise
// interaction re-emit their widgets each frame through a `build` proc. Geometry
// and interaction resolve against the *previous* frame, so most interaction
// tests run several frames: one (or more) to establish geometry, then the
// press/release frames where hover/click resolve.

SCREEN :: wynn.vec2{800, 600}

// Pushes a leaf node under the current container with the given constraints and
// returns its index. (The frame-local analogue of the old retained `make`.)
leaf :: proc(ctx: ^wynn.Context, cons: wynn.Constraints) -> int {
	idx := wynn.push_node(ctx)
	ctx.nodes[idx].constraints = cons
	return idx
}

// Runs one full frame: begin -> build -> end. `build` re-emits the UI from the
// caller's state each time it is called.
frame :: proc(ctx: ^wynn.Context, build: proc(ctx: ^wynn.Context, st: ^$T), st: ^T) {
	wynn.begin_frame(ctx, SCREEN)
	build(ctx, st)
	wynn.end_frame(ctx)
}

// Moves the cursor to `p`, presses the left button, then runs a frame. The
// press is captured in begin_frame against the previous frame's geometry.
press_frame :: proc(ctx: ^wynn.Context, p: wynn.vec2, build: proc(ctx: ^wynn.Context, st: ^$T), st: ^T) {
	wynn.input_mouse_move(ctx, p)
	wynn.input_mouse_button_down(ctx, .Left)
	frame(ctx, build, st)
}

// Releases the left button, then runs a frame. Click resolution (press and
// release on the same widget) lands on this frame.
release_frame :: proc(ctx: ^wynn.Context, build: proc(ctx: ^wynn.Context, st: ^$T), st: ^T) {
	wynn.input_mouse_button_up(ctx, .Left)
	frame(ctx, build, st)
}

// A full click at `p`: press frame then release frame. Assumes the target's
// geometry was already established by an earlier frame.
click :: proc(ctx: ^wynn.Context, p: wynn.vec2, build: proc(ctx: ^wynn.Context, st: ^$T), st: ^T) {
	press_frame(ctx, p, build, st)
	release_frame(ctx, build, st)
}

// Counts overlay-layer nodes (layer > 0) in the current frame — used to detect
// whether a dropdown/floating element was emitted.
overlay_count :: proc(ctx: ^wynn.Context) -> int {
	n := 0
	for node in ctx.nodes {
		if node.layer > 0 {
			n += 1
		}
	}
	return n
}
