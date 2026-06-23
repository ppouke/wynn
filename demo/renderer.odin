package main

import gl "vendor:OpenGL"
import "core:fmt"
import "core:os"
import stbtt "vendor:stb/truetype"

// ----------------------------------------------------------------------------
// Batched OpenGL renderer
//
// Every visible rect and every glyph becomes two triangles in one vertex
// buffer, drawn with a single glDrawArrays call. Solid rects and text share
// one texture: the font is baked into a single-channel (R8) atlas, and a small
// white block is reserved in a corner so solid quads can sample alpha = 1.
// ----------------------------------------------------------------------------

ATLAS_W :: 512
ATLAS_H :: 512
FONT_PX :: 32
FIRST_CHAR :: 32 // space
NUM_CHARS :: 95 // through '~'

TEXT_WHITE :: [4]f32{1, 1, 1, 1}

Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	color: [4]f32,
}

Renderer :: struct {
	program:  u32,
	vao:      u32,
	vbo:      u32,
	tex:      u32,
	u_screen: i32,
	u_tex:    i32,
	verts:    [dynamic]Vertex,
	cdata:    [NUM_CHARS]stbtt.bakedchar,
	white_uv: [2]f32,
	font_px:  f32,
}

VERT_SRC :: `#version 330 core
layout(location=0) in vec2 a_pos;
layout(location=1) in vec2 a_uv;
layout(location=2) in vec4 a_color;
uniform vec2 u_screen;
out vec2 v_uv;
out vec4 v_color;
void main() {
	vec2 ndc = vec2(a_pos.x / u_screen.x * 2.0 - 1.0,
	                1.0 - a_pos.y / u_screen.y * 2.0);
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_uv = a_uv;
	v_color = a_color;
}
`

FRAG_SRC :: `#version 330 core
in vec2 v_uv;
in vec4 v_color;
uniform sampler2D u_tex;
out vec4 frag;
void main() {
	float a = texture(u_tex, v_uv).r;
	frag = vec4(v_color.rgb, v_color.a * a);
}
`

renderer_init :: proc(r: ^Renderer) -> bool {
	r.font_px = f32(FONT_PX)

	// --- bake font atlas ---
	font := load_font_data()
	atlas := make([]byte, ATLAS_W * ATLAS_H)
	defer delete(atlas)
	if font != nil {
		stbtt.BakeFontBitmap(
			raw_data(font),
			0,
			FONT_PX,
			raw_data(atlas),
			ATLAS_W,
			ATLAS_H,
			FIRST_CHAR,
			NUM_CHARS,
			raw_data(r.cdata[:]),
		)
		delete(font)
	} else {
		fmt.eprintln("WARN: no font found; text will not render")
	}

	// Reserve a 2x2 white block (the baker packs from the top, so the
	// bottom-right corner is free) for solid-color quads.
	wx, wy := ATLAS_W - 2, ATLAS_H - 2
	for yy in 0 ..< 2 {
		for xx in 0 ..< 2 {
			atlas[(wy + yy) * ATLAS_W + (wx + xx)] = 255
		}
	}
	r.white_uv = {(f32(wx) + 0.5) / ATLAS_W, (f32(wy) + 0.5) / ATLAS_H}

	// --- upload atlas texture ---
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.GenTextures(1, &r.tex)
	gl.BindTexture(gl.TEXTURE_2D, r.tex)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RED, ATLAS_W, ATLAS_H, 0, gl.RED, gl.UNSIGNED_BYTE, raw_data(atlas))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	// --- shader program ---
	program, ok := gl.load_shaders_source(VERT_SRC, FRAG_SRC)
	if !ok {
		fmt.eprintln("ERROR: shader compilation failed")
		return false
	}
	r.program = program
	r.u_screen = gl.GetUniformLocation(r.program, "u_screen")
	r.u_tex = gl.GetUniformLocation(r.program, "u_tex")

	// --- vertex buffer / layout ---
	gl.GenVertexArrays(1, &r.vao)
	gl.GenBuffers(1, &r.vbo)
	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv))
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, color))
	gl.BindVertexArray(0)

	return true
}

load_font_data :: proc() -> []byte {
	candidates := []string{"C:\\Windows\\Fonts\\segoeui.ttf", "C:\\Windows\\Fonts\\arial.ttf"}
	for p in candidates {
		if data, ok := os.read_entire_file(p); ok {
			return data
		}
	}
	return nil
}

@(private = "file")
push_quad :: proc(r: ^Renderer, x0, y0, x1, y1, u0, v0, u1, v1: f32, col: [4]f32) {
	append(
		&r.verts,
		Vertex{{x0, y0}, {u0, v0}, col},
		Vertex{{x1, y0}, {u1, v0}, col},
		Vertex{{x1, y1}, {u1, v1}, col},
		Vertex{{x0, y0}, {u0, v0}, col},
		Vertex{{x1, y1}, {u1, v1}, col},
		Vertex{{x0, y1}, {u0, v1}, col},
	)
}

push_rect :: proc(r: ^Renderer, x, y, w, h: f32, col: [4]f32) {
	u, v := r.white_uv.x, r.white_uv.y
	push_quad(r, x, y, x + w, y + h, u, v, u, v, col)
}

push_text :: proc(r: ^Renderer, text: string, x, y: f32, col: [4]f32) {
	px, py := x, y
	for ch in text {
		if ch < FIRST_CHAR || ch >= FIRST_CHAR + NUM_CHARS {
			continue
		}
		q: stbtt.aligned_quad
		stbtt.GetBakedQuad(&r.cdata[0], ATLAS_W, ATLAS_H, i32(ch) - FIRST_CHAR, &px, &py, &q, true)
		push_quad(r, q.x0, q.y0, q.x1, q.y1, q.s0, q.t0, q.s1, q.t1, col)
	}
}

// Composite widget visuals (kept UI-agnostic: plain floats in).

draw_slider :: proc(r: ^Renderer, x, y, w, h, value: f32) {
	track_h: f32 = 6
	ty := y + (h - track_h) * 0.5
	push_rect(r, x, ty, w, track_h, {0.28, 0.28, 0.33, 1}) // track
	push_rect(r, x, ty, w * value, track_h, {0.35, 0.60, 0.95, 1}) // fill
	knob := h
	kx := x + value * (w - knob)
	push_rect(r, kx, y, knob, knob, {0.92, 0.92, 0.96, 1}) // knob
}

draw_toggle :: proc(r: ^Renderer, x, y, w, h, value: f32) {
	on := value >= 0.5
	if w > h * 1.5 {
		// switch: pill background + sliding knob
		bg: [4]f32 = {0.35, 0.35, 0.40, 1}
		if on {
			bg = {0.30, 0.75, 0.45, 1}
		}
		push_rect(r, x, y, w, h, bg)
		knob := h - 4
		kx := x + 2
		if on {
			kx = x + w - knob - 2
		}
		push_rect(r, kx, y + 2, knob, knob, {1, 1, 1, 1})
	} else {
		// checkbox: box + inner fill when on
		push_rect(r, x, y, w, h, {0.35, 0.35, 0.40, 1})
		if on {
			m: f32 = 4
			push_rect(r, x + m, y + m, w - 2 * m, h - 2 * m, {0.40, 0.70, 0.95, 1})
		}
	}
}

text_width :: proc(r: ^Renderer, text: string) -> f32 {
	w: f32 = 0
	for ch in text {
		if ch < FIRST_CHAR || ch >= FIRST_CHAR + NUM_CHARS {
			continue
		}
		w += r.cdata[i32(ch) - FIRST_CHAR].xadvance
	}
	return w
}

renderer_flush :: proc(r: ^Renderer, screen_w, screen_h: f32) {
	gl.Viewport(0, 0, i32(screen_w), i32(screen_h))
	gl.ClearColor(0.10, 0.10, 0.12, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(r.program)
	gl.Uniform2f(r.u_screen, screen_w, screen_h)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, r.tex)
	gl.Uniform1i(r.u_tex, 0)

	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(r.verts) * size_of(Vertex), raw_data(r.verts), gl.STREAM_DRAW)
	gl.DrawArrays(gl.TRIANGLES, 0, i32(len(r.verts))) // single draw call
}
