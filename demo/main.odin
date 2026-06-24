package main

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import wynn ".."
import cl "../components_library"

// Handles the demo needs to reference each frame.
UI :: struct {
	menus:        [3]cl.Menu,
	action_label: wynn.Handle,
	btn_inc:      wynn.Handle,
	btn_dec:      wynn.Handle,
	count_label:  wynn.Handle,
	slider:       wynn.Handle,
	slider_label: wynn.Handle,
	check:        wynn.Handle,
	sw:           wynn.Handle,
}

// OpenGL proc loader, fed to gl.load_up_to via SDL's GL_GetProcAddress.
gl_set_proc :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = rawptr(sdl.GL_GetProcAddress(name))
}

build_ui :: proc(ctx: ^wynn.Context) -> UI {
	ui: UI

	// A toolbar with three hover-to-open dropdown menus.
	tb := cl.toolbar(ctx, ctx.screen)
	ui.menus[0] = cl.menu(ctx, tb, "File", {"New", "Open", "Save", "Quit"})
	ui.menus[1] = cl.menu(ctx, tb, "Edit", {"Undo", "Redo", "Cut", "Copy", "Paste"})
	ui.menus[2] = cl.menu(ctx, tb, "View", {"Zoom In", "Zoom Out", "Reset"})

	// A panel laid out as a vertical column, below the toolbar.
	panel := wynn.column(ctx, ctx.screen, gap = 12, padding = {16, 16, 16, 16})
	pc := wynn.get_component(ctx, panel)
	pc.rect.pos = {40, 46}
	pc.constraints.pref_size = {320, 420}
	pc.color = {0.15, 0.16, 0.20, 1}

	ui.action_label = wynn.label(ctx, panel, "Ready", text_size = 16, size = {288, 22})

	wynn.label(ctx, panel, "wynn demo", text_size = 28, size = {288, 36})

	// A row of two buttons.
	bar := wynn.row(ctx, panel, gap = 10)
	wynn.get_component(ctx, bar).constraints.pref_size = {288, 32}
	ui.btn_inc = wynn.button(ctx, bar, "+1", size = {80, 32})
	ui.btn_dec = wynn.button(ctx, bar, "-1", size = {80, 32})

	ui.count_label = wynn.label(ctx, panel, "Count: 0", text_size = 20, size = {288, 28})

	// A slider with a live value readout.
	srow := wynn.row(ctx, panel, gap = 10)
	wynn.get_component(ctx, srow).constraints.pref_size = {288, 22}
	ui.slider = wynn.slider(ctx, srow, value = 0.5, size = {200, 20})
	ui.slider_label = wynn.label(ctx, srow, "50", text_size = 16, size = {70, 20})

	// A checkbox and a switch, each with a label.
	trow := wynn.row(ctx, panel, gap = 10)
	wynn.get_component(ctx, trow).constraints.pref_size = {288, 24}
	ui.check = wynn.checkbox(ctx, trow, checked = true, size = {22, 22})
	wynn.label(ctx, trow, "Check", text_size = 16, size = {64, 22})
	ui.sw = wynn.toggle_switch(ctx, trow, on = false, size = {44, 22})
	wynn.label(ctx, trow, "Switch", text_size = 16, size = {72, 22})

	// A 4-column grid of colour swatches.
	g := wynn.grid(ctx, panel, columns = 4, gap = {6, 6})
	wynn.get_component(ctx, g).constraints.pref_size = {288, 60}
	swatches := [4][4]f32 {
		{0.85, 0.30, 0.30, 1},
		{0.30, 0.80, 0.45, 1},
		{0.30, 0.55, 0.90, 1},
		{0.90, 0.80, 0.30, 1},
	}
	for col in swatches {
		sw := wynn.new_child(ctx, g)
		s := wynn.get_component(ctx, sw)
		s.constraints.pref_size = {64, 28}
		s.color = col
	}

	return ui
}

build_vertices :: proc(r: ^Renderer, data: []wynn.Render_Data) {
	clear(&r.verts)
	for rd in data {
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
	ui := build_ui(ctx)

	count := 0
	open_menu := -1
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
		wynn.update_screen_size(ctx, {f32(w), f32(h)})

		wynn.process_input(ctx)

		// Host reactions that mutate the tree run between input and layout, so
		// menu open/close positions land in this frame's solve.
		if it := cl.menu_bar_update(ctx, ui.menus[:], &open_menu); !wynn.handle_is_null(it) {
			wynn.get_component(ctx, ui.action_label).text = wynn.get_component(ctx, it).text
		}
		if wynn.was_clicked(ctx, ui.btn_inc) {
			count += 1
		}
		if wynn.was_clicked(ctx, ui.btn_dec) {
			count -= 1
		}

		// Refresh the count label. The buffer lives for this iteration, which
		// is all we need: render() copies the string and we draw it below.
		buf: [64]u8
		wynn.get_component(ctx, ui.count_label).text = fmt.bprintf(buf[:], "Count: %d", count)

		// Live readout of the slider value (0..100).
		sbuf: [32]u8
		sval := int(wynn.get_component(ctx, ui.slider).value * 100 + 0.5)
		wynn.get_component(ctx, ui.slider_label).text = fmt.bprintf(sbuf[:], "%d", sval)

		wynn.process_ui(ctx)

		data := wynn.render(ctx, context.allocator)
		build_vertices(&r, data)
		delete(data)

		renderer_flush(&r, f32(w), f32(h))
		sdl.GL_SwapWindow(window)
	}
}
