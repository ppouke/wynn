# wynn

A small **immediate-mode UI layout library** written in [Odin](https://odin-lang.org/).

wynn keeps the whole UI as a tree of components in a fixed-size pool, referenced
by **generational handles** (not pointers) over an **intrusive parent/child
list**. Each frame it solves layout, resolves input, and emits a flat list of
render data for your own renderer to draw. The library itself has **no rendering
or windowing dependency** — a batched SDL3 + OpenGL demo lives in `demo/` as a
reference host.

> Status: experimental / work in progress. See [`DESIGN.md`](DESIGN.md) for the
> full design rationale and decision log.

## Features

- **Generational handles** — freeing a slot invalidates stale handles instead of
  silently aliasing a reused one.
- **Intrusive tree** — O(1) parenting/reparenting/removal with a slot free-list.
- **Two-pass layout solver** — measure (bottom-up) then arrange (top-down).
- **Two positioning models per node**:
  - **anchors + margins** with per-axis min/max/preferred sizes, and
  - **flow containers**: `Row` / `Column` / `Grid`.
- **Interaction** — hover, mouse capture, focus, click; framework-driven
  `Move` (drag), `Slide` (slider), and `Toggle` (checkbox/switch) behaviors.
- **Widgets** — `label`, `button`, `checkbox`, `toggle_switch`, `slider`,
  `row`, `column`, `grid`, and a `toolbar` + dropdown `menu` — all thin sugar
  over the core (no special-casing in the solver/renderer/input passes).

## Quick start

```odin
import wynn ".."

ctx := wynn.initialize(context.allocator, {800, 600})

// Build a retained tree once.
panel := wynn.column(ctx, ctx.screen, gap = 12, padding = {16, 16, 16, 16})
wynn.get_component(ctx, panel).constraints.pref_size = {300, 160}
wynn.get_component(ctx, panel).color = {0.15, 0.16, 0.20, 1}

wynn.label(ctx, panel, "Hello, wynn", text_size = 24, size = {280, 32})
ok := wynn.button(ctx, panel, "OK", size = {80, 32})

// Each frame:
//   1. feed host events:  wynn.input_mouse_move / input_mouse_button_down / ...
//   2. resolve + lay out:
wynn.update_screen_size(ctx, {win_w, win_h})
wynn.process_input(ctx) // hover/click/drag resolution
wynn.process_ui(ctx)    // layout solve

if wynn.was_clicked(ctx, ok) {
	// react to the click
}

//   3. emit render data and draw it with your own renderer:
data := wynn.render(ctx, context.allocator)
defer delete(data, context.allocator)
for rd in data {
	// rd.rect, rd.color, rd.traits, rd.text, rd.text_size, rd.value
}
```

The frame order is always **events → `process_input` → `process_ui` →
`render` → draw**.

### Reading widget state

```odin
cb := wynn.checkbox(ctx, panel, checked = true)
sl := wynn.slider(ctx, panel, value = 0.5)
// ...after process_input:
on  := wynn.get_component(ctx, cb).value >= 0.5
amt := wynn.get_component(ctx, sl).value // 0..1
```

## Building & running

Requires the Odin compiler (uses the bundled `vendor:sdl3`, `vendor:OpenGL`, and
`vendor:stb/truetype`).

**Tests**

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

The demo shows a panel with a title, `+1`/`-1` buttons with a live counter, a
slider with a readout, a checkbox, a switch, and a grid of colour swatches.

## Layout & files

| File | Responsibility |
|------|----------------|
| `wynn.odin` | `Context`, `Component`, `Handle`, `Rect`, `Constraints`, `Layout`, init |
| `component.odin` | pool allocation, generational handles, intrusive tree ops |
| `layout.odin` | measure/arrange solver, flow containers, `rect_contains` |
| `input.odin` | input feed, `process_input`, hit-testing, interaction queries |
| `render.odin` | `render` — emits `[]Render_Data` in painter's order |
| `core.odin` | base widget constructors (label/button/checkbox/slider/row/column/grid) |
| `components_library/` | composite widgets (separate package): `toolbar.odin`, `menu.odin`, `floating.odin` |
| `test/` | unit tests (separate package) |
| `demo/` | SDL3 + OpenGL reference host (separate package) |

`MAX_COMPONENTS` is a compile-time config (`-define:WYNN_MAX_COMPONENTS=N`,
default 1024).

## License

[MIT](LICENSE) © 2026 Sakaria Pouke
