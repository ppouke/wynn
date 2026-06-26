# wynn — Design Document

An **immediate-mode** UI layout library. Each frame the app calls `begin_frame`,
emits widgets (which build a transient tree of `Node`s in a per-frame arena),
then `end_frame` (which solves layout) and `render` (which emits flat draw
data). Nothing is retained between frames except a little interaction state
keyed by explicit, hashed IDs — so the UI is a pure function of application
state and there is no tree to keep in sync.

Status legend: **Decided** (implemented or committed) · **Planned** (decided,
not yet built) · **Deferred** (intentionally postponed).

> **History:** wynn began as a retained-mode library (a generational-handle
> component pool with explicit add/remove/reparent). It was reworked into
> immediate mode: the pool, handles, and tree-mutation machinery are gone,
> replaced by a per-frame arena. The layout/coordinate/input/flow decisions
> below survived the transition largely intact; the identity, lifetime, and
> relayout decisions were rewritten. Sections still tagged with retained-mode
> rationale have been updated to the current model.

---

## 0. Foundation (implemented)

- `Context` owns everything: `nodes` (the current frame, built between
  `begin_frame`/`end_frame`), `prev_nodes` (last frame, already solved — the
  geometry we hit-test and measure against), a `stack` of open container indices
  (top = current parent), `screen_size`, `input`, the interaction state
  (`hot`/`hot_node`/`active`/`focused`), and the `allocator`.
- `nodes`/`prev_nodes` are `[dynamic]Node` arenas. They are **swapped** each
  frame and the new front is cleared — no per-frame allocation once they reach
  steady-state capacity.
- Node 0 is always the **screen root**, pushed by `begin_frame` and sized to the
  screen. `NO_NODE` (`-1`) is the "no node" link sentinel.
- `initialize(allocator, screen_size) -> ^Context`; pair with `destroy`. No
  compile-time size cap — the arenas grow as needed.

---

## 1. Identity — **Decided: hashed string ID, frame-local node indices**

Two distinct notions of "which node":

- **Within a frame**, nodes refer to each other by plain `int` indices into
  `Context.nodes` (`parent`, `first_child`, `last_child`, `next_sibling`;
  `NO_NODE` = none). These are valid only for the current frame and are rebuilt
  from scratch every frame.
- **Across frames**, an interactive widget has a stable `ID :: distinct u64`,
  produced by `get_id(string)` (FNV-1a hash of a caller-supplied string).
  `0` means "non-interactive" (the default). The caller guarantees uniqueness;
  derived ids (e.g. per-item menu ids) are built by hashing/xor-ing a base id.

- **Rationale:** Immediate mode rebuilds the tree each frame, so node links only
  need to live one frame — an `int` index is the cheapest possible reference and
  there is no lifetime/aliasing hazard to guard against. Persistent identity is
  needed *only* for interaction continuity (which widget is hovered/held across
  frames), and a hashed caller string supplies that without any retained tree.
- **Replaces** the old generational `Handle{index, generation}` + occupancy/
  generation tables: with no pool and no slot reuse, there is nothing to
  invalidate, so the entire handle-safety apparatus is unnecessary.
- **Caveat (the IMGUI tax):** id collisions are a caller error and silently
  merge interaction state; loop-generated widgets must derive distinct ids.

## 2. Memory — **Decided: swapped per-frame arenas**

`begin_frame` swaps `nodes` and `prev_nodes`, then `clear`s the new front
(length 0, capacity retained). Widgets append nodes during the frame.

- **Rationale:** O(1) "allocation" by bump within a `[dynamic]Node`; after the
  first few frames the arena no longer grows, so steady-state frames do zero
  heap work. Keeping last frame's solved nodes around (rather than discarding)
  gives hit-testing and `prev_rect` real geometry to work against.
- **Pointer discipline:** because appending may reallocate the arena, callers
  must **not** hold a `^Node` across a `push_node`. Widgets fetch the index from
  `push_node`, set fields, and re-fetch by index after any further push. (The
  layout solver, which appends nothing, may hold pointers within a pass.)
- **Replaces** the old free-stack + bump-pointer slot recycling; slot recycling
  only existed to manage a persistent pool, which no longer exists.

## 3. Data layout — **Decided: AoS, single `Node` struct**

One contiguous `[dynamic]Node`. `Render_Data` is a separate flat DTO emitted by
`render`, **derived** from the solved tree, not stored.

- **Rationale:** Layout/render/hit-test passes touch most of a node's fields
  together, so AoS is cache-friendly for the linear walks. Simpler code.
- **Revisit if:** profiling shows a hot pass that touches only one field across
  all nodes — then split that field into a parallel array.

## 4. Tree links — **Decided: embedded, singly-linked children, build-order**

`Node` embeds `parent`, `first_child`, `last_child`, `next_sibling` (indices).
There is **no `prev_sibling`** — the tree is built once, front to back, and
never edited mid-frame, so a singly-linked child list suffices.

- `push_node` appends a node and links it under the current container (the stack
  top) via `link_child`. `begin_container`/`begin_overlay` push the node onto
  `stack`; `pop_container`/`end_overlay` pop it (never popping the root).
- **Rationale:** Immediate mode never reparents, removes, or reorders a live
  node — it just appends in call order. That removes the need for the doubly-
  linked list, `unlink`, `bring_to_front`, and the reorder ops the retained
  design carried. Draw/hit order falls out of array order + layer (see §6, §11).
- **Replaces** the retained doubly-linked, reorderable child list.

## 5. Layering / overlays — **Decided: `layer` field + parent-to-root escape**

Each node has an `int layer` (0 = normal content). A child inherits its parent's
layer by default. `begin_overlay(pos, size, …)` appends a node parented to the
**screen root** (not the current container) on `layer = 1`, placed absolutely at
`pos`.

- **Rationale:** Dropdowns and floating windows must draw above and hit-test
  before normal content regardless of where in the call tree they are emitted.
  Parenting to the root escapes the current container's clip/layout; the higher
  layer wins in both render order (§6) and hit-testing (§11). This is the
  immediate-mode replacement for the retained "re-append to front" popup trick.
- Used by `components_library` `menu` (dropdown) and `floating` (window).

## 6. Layout traversal — **Decided: two-pass, recursive over the arena**

`solve_layout` (called by `end_frame`) runs:

- **measure** — bottom-up: each node's intrinsic `rect.size` = `pref_size`
  clamped to `[min_size, max_size]` (a `max` component of 0 = unbounded).
- **arrange** — top-down: each node resolves its children into `global_rect`,
  then recurses. A container with `layout.kind == .None` positions each child by
  its own anchors (`arrange_one`); a container with a flow kind flows its
  children and **ignores their anchors** (`arrange_flow`).

- **Render order:** the arena is built in painter order (parent before children,
  siblings in call order), so `render` emits it as a flat slice by index. It
  emits **layer by layer** (low first) so overlays land on top. Index 0 (root)
  is skipped. Returns `[]Render_Data` allocated from a caller-supplied allocator
  (caller frees) — see the allocator-returns-slice convention.
- **Walks** currently recurse via `first_child`/`next_sibling`; convert to
  iterative if tree depth ever becomes a concern.
- **Extension point — content sizing:** `measure` resolves size purely from a
  node's own constraints today (callers pass explicit `pref_size`). Parent-fits-
  children sizing would slot into `measure` after the child loop. This is the
  one place immediate mode constrains us: true multi-pass intrinsic sizing
  either needs a second forward pass or must read last frame's sizes from
  `prev_nodes`. **Not yet built** — flagged as the main open layout question.

## 7. Coordinates — **Decided: AABB (origin + size), axis-aligned**

`Rect :: struct { pos, size: vec2 }`. A node carries a local `rect` (origin used
for unanchored placement / absolute overlays) and a resolved `global_rect`
filled by arrange. The root's rect is `{ {0,0}, screen_size }`.

- **Rationale:** No rotation requirement → four corners are redundant. Half the
  storage, far simpler constraint math and hit-testing.
- **Revisit if:** rotation/transforms are ever required → local affine transform
  composed down the tree.

## 8. Layout model — **Decided: constraints/anchors + flow containers**

Per node, exactly one positioning authority (the **precedence rule**): the
parent's layout kind if it has one, else the child's own anchors.

- **`Constraints`:** `anchors` (bit_set over Left/Top/Right/Bottom) + `margins`
  (`Sides`, distance per pinned edge) + per-axis `min_size`/`max_size`/
  `pref_size`. Anchoring both edges of an axis stretches it; one edge fixes that
  side and the size comes from `pref_size`; neither edge → unanchored, placed at
  local `rect.pos`. Resolved per-axis by `resolve_axis` in `layout.odin`.
- **Flow containers:** a node may set `layout: Layout` with
  `kind = .Row/.Column/.Grid` plus `gap`, `padding`, `columns`. Arrange flows
  the node's direct children within its padded content rect; each child keeps
  its measured size. Grid uses a fixed `columns` count with equal-width columns;
  rows advance by the tallest item. `.None` (default) = anchor-based. The two
  models nest freely.
- **Deferred:** main-axis flex-grow/shrink (items take their measured size, not
  a distributed share); cross-axis stretch/alignment; a per-child opt-out to
  escape a parent's flow and use its own anchors.

## 9. Relayout strategy — **Decided: full rebuild + full solve every frame**

The arena is rebuilt and `solve_layout` re-solves the whole tree each frame.

- **Rationale:** This is the essence of immediate mode and the simplest correct
  baseline; fine for small/medium UIs and zero sync bugs by construction.
- **Deferred:** caching across frames is intentionally *not* done — it would
  reintroduce the retained-mode sync problem. If a UI grows large enough to need
  it, the answer is a retained layout cache behind the immediate API, not a
  return to a retained front end.

## 10. Mode — **Decided: immediate**

The app emits the whole UI from current state every frame; wynn retains only
`prev_nodes` (for geometry queries) and the interaction ids. There is no
add/remove/reparent API and no persistent component the app holds onto.

- **Rationale:** Removes the hardest retained-mode problem (keeping the tree in
  sync with app state) and a large amount of machinery (pool, handles, lifetime,
  tree edits). Suits the target domain (tools/game UIs over SDL+GL). The app
  owns all widget state and passes it in (by pointer for stateful widgets).
- **Trade accepted:** caller-managed ids; one-frame latency on hover (§11); and
  the content-sizing constraint in §6.

## 11. Interaction — **Decided: prev-frame hit-test + press capture**

- **Input model** (`input.odin`): the host feeds raw events via `input_*` procs
  between frames. `Input` keeps held sets (`buttons_down`/`keys_down`) plus
  this-frame edges (`buttons_pressed`/`buttons_released`/`keys_pressed`)
  **accumulated from events** (a press+release within one frame is still seen).
  `mouse_delta`/`scroll_delta` accumulate motion. `end_frame` clears every
  per-frame edge/delta field after the solve.
- **Hover** (`update_hot`, called by `begin_frame`): `hit_test` finds the
  top-most node under the cursor in **last frame's** geometry (`prev_nodes`) —
  front-most = highest `layer`, then highest array index (painter order). Sets
  `hot_node` (index) and `hot` (its id). Index 0 (root) is never returned.
- **Capture / focus:** on a left press, `begin_frame` sets `active` and
  `focused` to the current `hot` id. `active` is held until the button releases
  (`end_frame` clears it on mouse-up) — this is mouse capture, so a drag keeps
  targeting the pressed widget even if the cursor leaves it.
- **Click resolution:** a widget reports a click on the frame where it is
  `active`, the left button was released, and `hot` is still itself (press and
  release on the same widget). See `button_id` in `core.odin`.
- **Stateful behavior is widget-resolved, app-owned state:** stateful widgets
  take their value **by pointer** (`checkbox`/`toggle_switch: ^bool`,
  `slider: ^f32`) and mutate it directly when active — the app owns the storage,
  wynn owns the gesture. `slider` reads the cursor x against the widget's
  `prev_rect`. The widget mirrors the value into the node's `value: f32` for the
  renderer. `Move` (window drag) is resolved similarly in `begin_floating`
  against an app-owned `^vec2`.
- **Queries:** `is_hot`/`is_active`/`is_focused(id)` and `mouse_over_ui` (is the
  cursor over any node but the background — e.g. to decide whether UI should
  swallow the mouse vs. pass it to the world behind).
- **Press feedback for free:** `render` darkens a `.Press` node's color by
  `PRESS_DARKEN` while it is `active`, so every renderer shows press feedback
  without host code. Visual only — the click *action* is still host-driven.
- **Frame order:** feed events → `begin_frame` (swap, push root, resolve hover,
  capture press) → emit widgets → `end_frame` (solve, release capture, clear
  input edges) → `render`. Hover uses the previous frame's rects (standard
  one-frame latency); drags mutate app state during emission and land in the
  same frame's solve.

## 12. Widget layer — **Decided: thin procedures over the core API**

Two tiers, two packages:

- **`core.odin`** (`package wynn`) — base widgets that push a node, set fields,
  and resolve interaction inline:
  - Containers (begin/end pairs): `begin_row`/`begin_column`/`begin_grid`
    (flow), `begin_panel` (colored, Column by default). `anchor(edges, margins)`
    overrides the *most recently emitted* widget's placement within a `.None`
    parent (call it immediately after the widget).
  - Leaves: `label` (non-interactive text), `button`/`button_id` (returns true
    on click), `checkbox`/`toggle_switch` (`^bool`, returns changed),
    `slider` (`^f32` in [0,1], returns changed). (`toggle_switch`, not `switch`
    — Odin keyword.)
- **`components_library/`** (`package components_library`, imports `wynn`) —
  composite widgets, one file each, used as `cl.menu(…)` alongside
  `wynn.button(…)`. (Separate package because Odin makes every directory a
  package; this is a layer *on* the engine.)
  - `toolbar` — full-width top-pinned `Row`; emit `menu`s/widgets between
    `begin_toolbar`/`end_toolbar`.
  - `menu` — a click-to-toggle dropdown. The "which menu is open" id is
    **caller-owned** (`open: ^ID`), so only one is open at a time; the dropdown
    is a `begin_overlay` column positioned under the title via `prev_rect`.
    Returns the index of the item clicked this frame, or -1. Closes on a press
    outside its title/items.
  - `floating` — a draggable window on the overlay layer at an app-owned
    `pos: ^vec2`; adds the `.Move` trait and applies `mouse_delta` to `pos`
    while active. Children arranged by `layout` (Column default).
- **Pure sugar:** widgets add no runtime state and no special cases in the
  solver/render/input passes. A `button` is a node with `.Press`+`.Text` traits,
  a `pref_size`, and text; a row is a node with a `Row` layout. Stateful widgets
  are a node with a trait (`.Toggle`/`.Slide`) and a `value`, with state owned
  by the caller's pointer.
- **Text storage:** a node carries `text`/`text_size`, copied into `Render_Data`
  by `render`. The host owns font metrics, measurement, and glyph drawing; wynn
  only stores and forwards the string + size (callers pass explicit `pref_size`).

## 13. Demo / host integration — **`demo/` (SDL3 + OpenGL)**

A manual test app showing the host-side contract, not part of the library.

- **SDL3** owns the window, GL context, and input; events translate into
  `input_*` calls. Per frame: poll events → `begin_frame(screen_size)` →
  `build_ui` (emit widgets from `App` state) → `end_frame` → `render(temp)` →
  build vertices → flush → swap → `free_all(temp)`. All UI state lives in `App`;
  wynn retains nothing.
- **Batched GL renderer** (`demo/renderer.odin`): every visible rect and glyph
  is appended as two triangles to one vertex buffer and drawn with a single
  `glDrawArrays`. Solid rects and text share one texture — the font is baked
  (stb_truetype) into an R8 atlas with a reserved white texel that solid quads
  sample, so no texture switch is needed.
- **Color convention (host-side):** a pure label (`Text` and not `Press`) draws
  its text in `color` with no background; everything else fills `color` and
  draws any text in white on top. `.Slide`/`.Toggle` nodes get composite visuals
  (`draw_slider`/`draw_toggle`) keyed off `value`. This resolves the "one color
  field" ambiguity at the renderer, not in the library.

Build: `odin build demo -out:demo/wynn_demo.exe` (needs `SDL3.dll` beside the
exe). The library proper has no SDL/GL dependency.

---

## Open items / follow-ups

1. **Content-driven sizing** (§6): let containers size to their children, within
   the single-pass / prev-frame-measurement constraint.
3. **Flow layout extras** (§8): main-axis flex-grow/shrink, cross-axis
   stretch/alignment, per-child flow opt-out.
4. **Resize trait** (§11): edge/corner grab detection + drag-to-resize
   (`Resize` is defined in `Traits` but not yet wired).
5. **Z-order raise on press** (§5, §11): raise a pressed floating window above
   its peers (needs a stable per-overlay ordering, since array order is rebuilt
   each frame).
6. **Iterative traversal** (§6) for layout/render/hit-test if depth grows.
7. **More widgets** (§12): text input (keyboard routing + editing), image/icon,
   radio groups, scroll container (needs a retained scroll offset, keyed by id).

Done: immediate-mode core — per-frame arena + swap, screen root, frame lifecycle
(§0, §2, §10); hashed-ID identity (§1); layered overlays (§5); two-pass solver
measure+arrange (§6, §8); AABB geometry (§7); constraints/anchors + Row/Column/
Grid flow (§8); render-data emission with layering + press feedback (§6, §11);
event-accumulation input + prev-frame hit-test + capture/focus/click (§11);
widget layer label/button/checkbox/toggle/slider + toolbar/menu/floating (§12);
SDL3+GL demo host (§13); test suite ported to immediate mode (`test/`, 39 tests).
