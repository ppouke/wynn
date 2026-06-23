# wynn — Design Document

A retained-mode UI layout library built on an intrusive parent/child tree over
a fixed-size component pool. Components are referenced by generational
`Handle`s rather than pointers, so the pool can move/reuse memory without
dangling references.

Status legend: **Decided** (implemented or committed) · **Planned** (decided,
not yet built) · **Deferred** (intentionally postponed).

---

## 0. Foundation (implemented)

- `Context` owns everything: a `[MAX_COMPONENTS]Component` pool, occupancy
  (`used`), per-slot `generations`, a `free_slots` stack, the `next_empty_slot`
  bump pointer, the `screen` root handle, and `input`.
- Slot 0 is the reserved **null component**; `NULL_HANDLE` (the zero value of
  `Handle`) refers to it. Invalid/stale handles resolve to it via
  `get_component`, which doubles as a safe write sink.
- `MAX_COMPONENTS` is a compile-time `#config` (default 1024).

---

## 1. Handle safety — **Decided: generational struct handle**

```odin
Handle :: struct { index: u32, generation: u32 }
```

A handle is valid only if `used[index]` and `generations[index] ==
handle.generation`. Freeing a slot bumps its generation, so every prior handle
to that slot becomes stale and resolves to the null component instead of
silently aliasing a new occupant.

- **Rationale:** Eliminates use-after-free/aliasing — the #1 hazard of an
  index-based pool. Explicit named fields chosen over bit-packing for
  readability (storage cost is negligible here).
- **Alternatives:** raw index (unsafe on reuse); bit-packed scalar (denser,
  less readable); pointers (break under pool relocation, no liveness check).

## 2. Slot allocation — **Decided: free-stack recycling + bump pointer**

`add_component` pops a reclaimed index from `free_slots` if any, otherwise
advances `next_empty_slot`; returns `NULL_HANDLE` when exhausted.
`remove_component` clears the slot, bumps its generation, and pushes the index.

- **Rationale:** O(1) alloc/free, no per-frame allocation, no fragmentation,
  bounded memory. Pairs naturally with generational handles.
- **Note:** Generation wraps at 2^32 — effectively unreachable for UI.
- **Alternatives:** intrusive free-list threaded through dead nodes' link
  fields (saves the `free_slots` array; revisit only if memory-constrained).

## 3. Data layout — **Decided: AoS, single `Component` struct**

One contiguous array of fat `Component` structs.

- **Rationale:** Layout/render/hit-test passes touch most of a node's fields
  together, so AoS is cache-friendly for tree walks. Simpler code.
- **Follow-up:** `Render_Data` currently duplicates fields from `Component`.
  Decision: render data is **derived** each frame from the resolved tree, not
  separately stored — treat `Render_Data` as an output/DTO, not pool state.
- **Revisit if:** profiling shows a hot pass that touches only one field (e.g.
  positions) across all nodes — then split that field into a parallel SoA array.

## 4. Where links live — **Decided: embedded in `Component` (single tree)**

`parent`, `first_child`, `last_child`, `next_sibling`, `prev_sibling` live
directly in `Component`.

- **Rationale:** Only one list type today (the tree). Embedding is the simplest
  intrusive form and keeps a node self-describing.
- **Revisit if:** we add more per-node lists (e.g. a dirty list, a free-list
  threaded through nodes) — then factor links into a reusable `Node` the
  component embeds, so the same list ops serve every list.

## 5. Child ordering & sibling links — **Decided: doubly-linked, ordered**

Children form a doubly-linked list; **sibling order is the logical/draw order**
(first child drawn first / underneath, hit-testing walks children in reverse).

- Implemented: `set_parent` appends as last child + full `unlink`.
- **Planned ops:** `insert_before`, `insert_after`, `move_to_front`,
  `move_to_back` — UI needs explicit reordering for z-order and dynamic
  insertion. Build when the first caller needs them.
- **Rationale:** Doubly-linked gives O(1) insert/remove/reorder anywhere, which
  retained UIs need constantly.

## 6. Traversal — **Decided: two-pass layout, iterative walks**

- **Layout:** two-pass — **measure bottom-up** (resolve each node's desired
  size from children + its own min/max constraints), then **arrange top-down**
  (assign each child a concrete rect within the parent's resolved rect).
- **Render:** top-down, parent before child (painter's order). Implemented:
  `render(ctx, allocator) -> []Render_Data` in `render.odin` — allocates and
  returns a flat slice (caller frees); skips the screen root; an invisible node
  hides its subtree. `text`/`text_size` left empty pending text storage.
- **Hit-test:** top-down, children in reverse z-order, deepest hit wins.
  Implemented: `hit_test(ctx, point) -> Handle` in `input.odin`; a node only
  descends if the point is in its own rect (assumes children clip to parent).
  `process_input` resolves `ctx.hovered` from the mouse position each frame.
- Covered by `test/hit_render_test.odin` (topmost wins, deepest child, empty →
  screen, outside → null, painter order, hidden subtree).
- **Walks:** layout/render/hit-test currently recurse; convert to iterative
  (via `first_child`/`next_sibling`/`parent`) if tree depth becomes a concern.
- New components default `visible = true`.

## 7. Coordinates — **Decided: AABB (origin + size), axis-aligned**

Replace four-corner `Positions` with `{ pos: vec2, size: vec2 }`.

- Implemented: `Rect :: struct { pos, size: vec2 }`. `Component` holds a local
  `rect` (origin relative to parent) and a resolved `global_rect` filled by the
  arrange pass. `initialize`/`update_screen_size` set the root rect to
  `{ {0,0}, screen_size }`. `Render_Data` carries the resolved `rect`.
- **Rationale:** No rotation requirement → corners are redundant. Half the
  storage, far simpler constraint math and hit-testing.
- **Revisit if:** rotation/transforms are ever required → move to a local
  affine transform composed down the tree.

## 8. Layout model — **Decided: constraint/anchor based**

Children are positioned by anchoring edges to the parent (and/or siblings) plus
min/max size constraints — matching the existing `Constraints` field.

- The measure pass clamps `pref_size` to `[min_size, max_size]`; the arrange
  pass resolves anchors into the concrete rect.
- Implemented `Constraints`: `anchors` (`Anchor_Edges` bit_set over
  Left/Top/Right/Bottom) + `margins` (`Sides`: distance per pinned edge) +
  per-axis `min_size`/`max_size`/`pref_size` (`vec2`, `max_size` component 0 =
  unbounded). Anchoring both edges of an axis stretches; one edge fixes that
  side and size comes from `pref_size`.
- Implemented in `layout.odin`: `solve_layout` runs `measure` (bottom-up
  intrinsic size = pref clamped to min/max) then `arrange_children` (top-down,
  resolves anchors/margins into `global_rect`). `process_ui` calls it each
  frame. Covered by `test/solver_test.odin` (stretch, single-edge anchors,
  unanchored offset, min/max clamp, nesting).
- **Extension point:** content-driven sizing (parent fits children) slots into
  `measure` after the child loop without touching `arrange`.
- **Flow containers (implemented):** a node may set `layout: Layout` with
  `kind = .Row/.Column/.Grid` (plus `gap`, `padding`, `columns`). When set, the
  arrange pass flows that node's direct children and **ignores their anchors**;
  each child keeps its measured size. `.None` (default) = anchor-based. The two
  models coexist per-node and nest freely (a flow container can hold another).
  Grid uses a fixed `columns` count with equal-width columns across the content
  rect; rows advance by the tallest item. See `arrange_flow` in `layout.odin`,
  covered by `test/flow_test.odin`.
- **Precedence rule:** exactly one positioning authority per child — the
  parent's layout kind if set, else the child's own anchors.
- **Deferred:** main-axis flex-grow/shrink (items currently take their measured
  size, not a distributed share); cross-axis stretch/alignment options; a
  per-child `Floating` opt-out trait to escape a parent's layout.

## 9. Relayout strategy — **Decided: full tree every frame**

`process_ui` re-solves the entire tree each frame.

- **Rationale:** Simplest correct baseline; fine for small/medium UIs.
- **Deferred:** dirty-subtree tracking (a `dirty` flag + an intrusive dirty
  list, re-solving only affected subtrees). Design leaves room for it (see §4);
  build only when profiling demands.

## 10. Mode — **Decided: retained**

Persistent components with handles and explicit add/remove/reparent. The app
mutates a retained tree; wynn solves and emits render data each frame. (Not
immediate-mode.)

## 11. Interaction — **Decided: event-accumulation input + capture/click resolution**

- **Input model** (`input.odin`): the host feeds raw events via `input_*` procs
  between frames. `Input` keeps held sets (`buttons_down`/`keys_down`) plus
  this-frame edges (`buttons_pressed`/`buttons_released`/`keys_pressed`)
  **accumulated from events**, so a press+release within one frame is still
  observed. `mouse_delta`/`scroll_delta` accumulate motion. `process_input`
  consumes and then clears all per-frame fields.
- **Resolution** (`process_input`, once per frame, before `process_ui`):
  - `hovered` — top-most component under the cursor (from last frame's layout).
  - `active` — component that captured the primary (Left) press; held until
    release (mouse capture).
  - `focused` — set to `active` on press.
  - `clicked` — set when press and release land on the same component.
- **Spatial / value behavior** (framework-owned, like `Move`): components with
  the `Move` trait are dragged by `mouse_delta` while active (mutates
  `rect.pos`). `Slide` sets `value` in [0,1] from the cursor x within the rect
  (slider; click-to-jump works). `Toggle` flips `value` between 0 and 1 on
  click (checkbox/switch). These mutate the widget's *own* generic state, so
  the framework owns them; `Close`/`Hide`/`Press` (app intent) still don't.
  `Resize` (needs edge-grab detection) is deferred.
- **App-intent traits stay with the host:** `Close`/`Hide`/`Press` semantics are
  *not* hard-coded. The host polls `is_hovered` / `is_active` / `is_focused` /
  `was_clicked` and acts on the component's traits as it sees fit.
- **Frame order:** feed events → `process_input` → `process_ui` (layout) →
  `render`. Hover uses the previous frame's resolved rects (standard 1-frame
  latency); drags applied in `process_input` land in the same frame's layout.
- Covered by `test/interaction_test.odin` (hover, click on same, no-click on
  release elsewhere, Move drag, drag ignored without the trait).

## 12. Widget layer — **Decided: thin constructors over the core API**

- `core.odin` provides convenience constructors that wrap
  `add_component`+`set_parent`+field setup and return the new `Handle`:
  `label`, `button`, `checkbox`, `toggle_switch`, `slider`, `row`, `column`,
  `grid` (plus `new_child`). (`toggle_switch`, not `switch` — Odin keyword.)
- **Stateful widgets** store a normalized `value: f32` (0..1) on `Component`
  (also emitted in `Render_Data`): `checkbox`/`toggle_switch` use the `Toggle`
  trait (value 0/1); `slider` uses `Slide`. Behavior is resolved generically in
  `process_input` (§11) — read state back via `get_component(ctx, h).value`.
  Still no new runtime machinery: a checkbox is just a component with a trait
  and a value.
- They are **pure sugar** — no new runtime state, no special-casing in the
  solver/render/input passes. A `button` is a component with the `Press`+`Text`
  traits, a `pref_size`, and text; `row`/`column`/`grid` just set a `Layout`.
  Callers keep the returned handle to poll `was_clicked` / tweak fields.
- **Text storage:** `Component` now carries `text`/`text_size`, copied into
  `Render_Data` by `render`. (The host still owns font metrics/measurement and
  the actual glyph drawing; wynn only stores and forwards the string + size.)
- Config uses default + named args (e.g. `label(ctx, p, "Hi", text_size = 18)`).
- Covered by `test/widgets_test.odin`.

## 13. Demo / host integration — **`demo/` (SDL3 + OpenGL)**

A manual test app showing the host-side contract, not part of the library.

- **SDL3** owns the window, GL context, and input; events are translated into
  `input_*` calls. Frame order matches §11: poll events → `update_screen_size`
  → `process_input` → `process_ui` → `render` → draw → swap.
- **Batched GL renderer** (`demo/renderer.odin`): every visible rect and every
  glyph is appended as two triangles to one vertex buffer and drawn with a
  **single `glDrawArrays`**. Solid rects and text share one texture — the font
  is baked (stb_truetype) into an R8 atlas with a reserved **white texel** that
  solid quads sample (alpha = 1), so no texture switch is needed.
- **Color convention (host-side):** a pure label (`Text` and not `Press`) draws
  its text in `color` with no background; everything else fills `color` and
  draws any text in white on top. This resolves the "one color field" ambiguity
  at the renderer, not in the library.
- **Text measurement stays host-side:** widgets are given explicit `pref_size`;
  wynn forwards the string + size and the renderer owns glyph metrics.

Build: `odin build demo -out:demo/wynn_demo.exe` (needs `SDL3.dll` beside the
exe). The library proper has no SDL/GL dependency.

---

## Open items / follow-ups

0. **Flow layout extras** (§8): flex-grow/shrink on the main axis, cross-axis
   stretch/alignment, and a `Floating` opt-out trait for children that should
   ignore their parent's layout and use their own anchors.
1. **Resize trait** (§11): edge/corner grab detection + drag-to-resize.
2. **Z-order raise on press** (§5, §11): bring `active` to front (`move_to_back`
   of sibling list) on press, for window-style focus.
3. **Sibling reorder ops** (§5): `insert_before/after`, `move_to_front/back`.
4. **Content-driven sizing** (§6, §8): let containers size to their children
   (extension point already in `measure`).
5. **Iterative traversal** (§6) for layout/render/hit-test/remove if depth grows.
6. **More widgets** (§12): text input (needs keyboard routing + text editing),
   image/icon, panel/window (Move+Close+Resize wired), radio groups.

Done: generational handles (§1), slot recycling (§2), geometry → AABB (§7),
constraints → anchor/min/max spec (§8), layout solver / measure+arrange (§6, §8),
render-data emission + hit-testing + hover (§6), interaction model:
capture/focus/click + Move drag (§11), flow containers: Row/Column/Grid (§8),
text storage + widget layer: label/button/row/column/grid (§12).
