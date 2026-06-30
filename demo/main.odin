package main

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import wynn ".."
import cl "../components_library"

// OpenGL proc loader, fed to gl.load_up_to via SDL's GL_GetProcAddress.
gl_set_proc :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = rawptr(sdl.GL_GetProcAddress(name))
}

// All app state lives here — wynn retains nothing between frames.
App :: struct {
	count:     int,
	volume:    f32,
	checked:   bool,
	switched:  bool,
	open_menu: wynn.ID,
	win_pos:   wynn.vec2,
	action:    string,
	image:     wynn.Image_Handle,
}

FILE_ITEMS :: []string{"New", "Open", "Save", "Quit"}
EDIT_ITEMS :: []string{"Undo", "Redo", "Cut", "Copy", "Paste"}
VIEW_ITEMS :: []string{"Zoom In", "Zoom Out", "Reset"}

SWATCHES :: [4]wynn.vec4 {
	{0.85, 0.30, 0.30, 1},
	{0.30, 0.80, 0.45, 1},
	{0.30, 0.55, 0.90, 1},
	{0.90, 0.80, 0.30, 1},
}

// Builds the whole UI for one frame from current app state (immediate mode).
build_ui :: proc(ctx: ^wynn.Context, app: ^App) {
	// Toolbar with three click-to-open dropdown menus.
	cl.begin_toolbar(ctx)
	file, edit, view := FILE_ITEMS, EDIT_ITEMS, VIEW_ITEMS
	if i := cl.menu(ctx, &app.open_menu, "menu.file", "File", file); i >= 0 {
		app.action = file[i]
	}
	if i := cl.menu(ctx, &app.open_menu, "menu.edit", "Edit", edit); i >= 0 {
		app.action = edit[i]
	}
	if i := cl.menu(ctx, &app.open_menu, "menu.view", "View", view); i >= 0 {
		app.action = view[i]
	}
	cl.end_toolbar(ctx)

	// Main panel, anchored below the toolbar, laid out as a column.
	wynn.begin_panel(
		ctx,
		layout = {kind = .Column, gap = 12, padding = {16, 16, 16, 16}},
		constraints = {anchors = {.Left, .Top}, margins = {left = 40, top = 46}, pref_size = {320, 420}},
	)
	{
		wynn.label(ctx, app.action, 16, wynn.WHITE, {288, 22})

		wynn.begin_row(ctx, gap = 10, constraints = {pref_size = {288, 32}})
		if wynn.button(ctx, "inc", "+1", {80, 32}) {app.count += 1}
		if wynn.button(ctx, "dec", "-1", {80, 32}) {app.count -= 1}
		wynn.end_row(ctx)

		wynn.label(ctx, fmt.tprintf("Count: %d", app.count), 20, wynn.WHITE, {288, 28})

		wynn.begin_row(ctx, gap = 10, constraints = {pref_size = {288, 22}})
		wynn.slider(ctx, "vol", &app.volume, {200, 20})
		wynn.label(ctx, fmt.tprintf("%d", int(app.volume * 100 + 0.5)), 16, wynn.WHITE, {70, 20})
		wynn.end_row(ctx)

		wynn.begin_row(ctx, gap = 10, constraints = {pref_size = {288, 24}})
		wynn.checkbox(ctx, "chk", &app.checked, {22, 22})
		wynn.label(ctx, "Check", 16, wynn.WHITE, {64, 22})
		wynn.toggle_switch(ctx, "sw", &app.switched, {44, 22})
		wynn.label(ctx, "Switch", 16, wynn.WHITE, {72, 22})
		wynn.end_row(ctx)

		wynn.begin_grid(ctx, 2, gap = {6, 6}, constraints = {pref_size = {288, 60}})
		for c in SWATCHES {
			wynn.begin_panel(ctx, color = c, layout = {}, constraints = {pref_size = {64, 28}})
			wynn.end_panel(ctx)
		}
		wynn.end_grid(ctx)

		wynn.begin_row(ctx, gap = 10, constraints = {pref_size = {288, 64}})
		wynn.image(ctx, app.image, {64, 64})
		wynn.label(ctx, "image()", 16, wynn.WHITE, {120, 64})
		wynn.end_row(ctx)
	}
	wynn.end_panel(ctx)

	// Draggable floating window (overlaps the panel to show it floats on top).
	// None layout so children place themselves by anchors.
	cl.begin_floating(ctx, "win", &app.win_pos, {280, 170}, layout = wynn.Layout{})
	{
		wynn.label(ctx, "Floating window", 18, wynn.WHITE, {236, 24})
		wynn.anchor(ctx, {.Left, .Top}, {left = 12, top = 12})

		wynn.label(ctx, "drag my body", 14, wynn.WHITE, {236, 20})
		wynn.anchor(ctx, {.Left, .Top}, {left = 12, top = 40})

		if wynn.button(ctx, "winok", "OK", {80, 28}) {app.action = "Window: OK"}
		wynn.anchor(ctx, {.Right, .Bottom}, {right = 12, bottom = 12})
	}
	cl.end_floating(ctx)
}

build_vertices :: proc(r: ^Renderer, data: []wynn.Render_Data) {
	clear(&r.verts)
	clear(&r.batches)
	for rd in data {
		// An image draws its host texture filling the rect, tinted by color.
		if .Icon in rd.traits && rd.image != 0 {
			push_image(r, u32(rd.image), rd.rect.pos.x, rd.rect.pos.y, rd.rect.size.x, rd.rect.size.y, rd.color)
			continue
		}

		// Stateful widgets get composite visuals.
		if .Slide in rd.traits {
			draw_slider(r, rd.rect.pos.x, rd.rect.pos.y, rd.rect.size.x, rd.rect.size.y, rd.value)
			continue
		}
		if .Toggle in rd.traits {
			draw_toggle(r, rd.rect.pos.x, rd.rect.pos.y, rd.rect.size.x, rd.rect.size.y, rd.value)
			continue
		}

		// A pure label (Text but not pressable) draws text only; everything
		// else draws its background colour, and text on top if it has any.
		is_label := (.Text in rd.traits) && (.Press not_in rd.traits)

		if !is_label && rd.color.a > 0 {
			push_rect(r, rd.rect.pos.x, rd.rect.pos.y, rd.rect.size.x, rd.rect.size.y, rd.color)
		}

		if (.Text in rd.traits) && len(rd.text) > 0 {
			tcol := rd.color if is_label else TEXT_WHITE
			tw := text_width(r, rd.text)
			tx := rd.rect.pos.x + 8
			if rd.rect.size.x > tw + 16 {
				tx = rd.rect.pos.x + (rd.rect.size.x - tw) * 0.5 // centre horizontally
			}
			ty := rd.rect.pos.y + rd.rect.size.y * 0.5 + r.font_px * 0.32 // rough vertical centre
			push_text(r, rd.text, tx, ty, tcol)
		}
	}
}

main :: proc() {
	if !sdl.Init(sdl.INIT_VIDEO) {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		return
	}
	defer sdl.Quit()

	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, 0x0001) // CORE
	sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)

	window := sdl.CreateWindow("wynn demo", 900, 640, sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE)
	if window == nil {
		fmt.eprintln("CreateWindow failed:", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	gl_ctx := sdl.GL_CreateContext(window)
	if gl_ctx == nil {
		fmt.eprintln("GL_CreateContext failed:", sdl.GetError())
		return
	}
	defer sdl.GL_DestroyContext(gl_ctx)
	sdl.GL_MakeCurrent(window, gl_ctx)
	gl.load_up_to(3, 3, gl_set_proc)
	sdl.GL_SetSwapInterval(1)

	r: Renderer
	if !renderer_init(&r) {
		return
	}

	ctx := wynn.initialize(context.allocator, {900, 640})
	defer wynn.destroy(ctx)

	app := App {
		volume  = 0.5,
		checked = true,
		win_pos = {300, 300},
		action  = "Ready",
		image   = wynn.Image_Handle(r.demo_image),
	}

	running := true
	for running {
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			#partial switch ev.type {
			case .QUIT:
				running = false
			case .MOUSE_MOTION:
				wynn.input_mouse_move(ctx, {ev.motion.x, ev.motion.y})
			case .MOUSE_BUTTON_DOWN:
				if ev.button.button == sdl.BUTTON_LEFT {
					wynn.input_mouse_button_down(ctx, .Left)
				}
			case .MOUSE_BUTTON_UP:
				if ev.button.button == sdl.BUTTON_LEFT {
					wynn.input_mouse_button_up(ctx, .Left)
				}
			}
		}

		w, h: i32
		sdl.GetWindowSizeInPixels(window, &w, &h)

		wynn.begin_frame(ctx, {f32(w), f32(h)})
		build_ui(ctx, &app)
		wynn.end_frame(ctx)

		data := wynn.render(ctx, context.temp_allocator)
		build_vertices(&r, data)

		renderer_flush(&r, f32(w), f32(h))
		sdl.GL_SwapWindow(window)

		free_all(context.temp_allocator) // frees this frame's render slice + tprintf strings
	}
}
