# wynn

A small **immediate-mode UI layout library** written in [Odin](https://odin-lang.org/).

Each frame you emit widgets between `begin_frame` and `end_frame`; wynn builds a
transient node tree in a per-frame arena, solves layout, and emits a flat list
of render data for your own renderer to draw. Nothing is retained between frames
except a little interaction state keyed by explicit IDs — so the UI is a pure
function of your application state, with no tree to keep in sync. The library
itself has **no rendering or windowing dependency**; a batched SDL3 + OpenGL
demo lives in `demo/` as a reference host.

> Status: experimental / work in progress. See [`DESIGN.md`](DESIGN.md) for the
> full design rationale and decision log.

## Features

- **Immediate mode** — rebuild the UI from your state every frame; no retained
  tree, no handles, no lifetime management, no sync bugs.
- **Stable interaction by hashed string IDs** — widgets stay hovered/held across
  frames without a persistent tree.
- **Two-pass layout solver** — measure (bottom-up) then arrange (top-down).
- **Two positioning models per node**:
  - **anchors + margins** with per-axis min/max/preferred sizes, and
  - **flow containers**: `Row` / `Column` / `Grid`.
- **Interaction** — hover, mouse capture, focus, click; widgets resolve their
  own gestures (button click, slider drag, checkbox/switch toggle, window move)
  against **caller-owned** state.
- **Widgets** — containers (`begin_row`/`begin_column`/`begin_grid`/`begin_panel`),
  leaves (`label`, `button`, `checkbox`, `toggle_switch`, `slider`), plus a
  `toolbar` + dropdown `menu` and a `floating` window — all thin sugar over the
  core (no special-casing in the solver/renderer/input passes).

## Quick start

```odin
import wynn ".."

// All UI state lives in your app — wynn retains nothing between frames.
App :: struct {
	count:  int,
	volume: f32,
	on:     bool,
}
app: App

ctx := wynn.initialize(context.allocator, {800, 600})
defer wynn.destroy(ctx)

// Each frame:
//   1. feed host events *between* frames:
//        wynn.input_mouse_move / input_mouse_button_down / input_mouse_button_up / ...
//   2. build the whole UI from app state, between begin/end_frame:
wynn.begin_frame(ctx, {win_w, win_h})

wynn.begin_panel(
	ctx,
	color = {0.15, 0.16, 0.20, 1},
	layout = {kind = .Column, gap = 12, padding = {16, 16, 16, 16}},
	constraints = {pref_size = {300, 160}},
)
wynn.label(ctx, "Hello, wynn", text_size = 24, size = {280, 32})
if wynn.button(ctx, "ok", "OK", {80, 32}) {
	app.count += 1 // returns true on the frame it is clicked
}
wynn.slider(ctx, "vol", &app.volume)   // mutates app.volume (0..1) in place
wynn.checkbox(ctx, "chk", &app.on)     // mutates app.on in place
wynn.end_panel(ctx)

wynn.end_frame(ctx) // solves layout

//   3. emit render data and draw it with your own renderer:
data := wynn.render(ctx, context.temp_allocator)
for rd in data {
	// rd.rect, rd.color, rd.traits, rd.text, rd.text_size, rd.value
}
```

The frame order is always **events → `begin_frame` → emit widgets →
`end_frame` → `render` → draw**.

### Reading widget state

Interactive widgets report their result directly. Stateful widgets take their
value **by pointer** — you own the storage, wynn just mutates it — and return
`true` on the frame the value changed:

```odin
if wynn.button(ctx, "ok", "OK") {
	// clicked this frame
}
if wynn.checkbox(ctx, "chk", &app.on) {
	// app.on was toggled this frame
}
if wynn.slider(ctx, "vol", &app.volume) {
	// app.volume was dragged this frame
}
// app.on / app.volume are the source of truth, owned by you.
```

Each interactive widget needs an explicit string `id` that is unique among its
siblings; derive distinct ids for loop-generated widgets.

## Building & running

Requires the Odin compiler (the demo uses the bundled `vendor:sdl3`,
`vendor:OpenGL`, and `vendor:stb/truetype`; the library itself has no
dependencies).

**Tests** (39 tests, no rendering/windowing required)

```sh
odin test test
```

**Demo** (SDL3 + OpenGL, single-draw-call batched renderer with stb_truetype text)

```sh
odin build demo -out:demo/wynn_demo.exe
# copy the SDL3 runtime next to the exe (Windows):
copy "%ODIN_ROOT%\vendor\sdl3\SDL3.dll" demo\
demo\wynn_demo.exe
```

The demo shows a toolbar with dropdown menus, a panel with a title, `+1`/`-1`
buttons with a live counter, a slider with a readout, a checkbox, a switch, a
grid of colour swatches, and a draggable floating window.

## Layout & files

| File | Responsibility |
|------|----------------|
| `wynn.odin` | `Context`, `Node`, `ID`, `Rect`, `Constraints`, `Layout`; frame lifecycle + transient tree construction |
| `core.odin` | immediate-mode widgets (label/button/checkbox/toggle_switch/slider, begin_row/column/grid/panel, anchor) |
| `layout.odin` | measure/arrange solver, flow containers, `rect_contains` |
| `input.odin` | input feed, hover + hit-testing against the previous frame, interaction queries |
| `render.odin` | `render` — emits `[]Render_Data` in painter order (low layers first) |
| `components_library/` | composite widgets (separate package): `toolbar.odin`, `menu.odin`, `floating.odin` |
| `test/` | unit tests (separate package) |
| `demo/` | SDL3 + OpenGL reference host (separate package) |

## License

[MIT](LICENSE) © 2026 Sakaria Pouke
