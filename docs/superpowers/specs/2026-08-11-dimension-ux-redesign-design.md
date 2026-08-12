# HTU ScalePlus — Dimension UX redesign

Date: 2026-08-11
Status: approved

## Goal

Three changes to how dimensions are edited:

1. Remove the pet toolbar (the radial/rect command palette drawn beside the selection).
2. Replace the `UI.inputbox` resize dialog with VCB entry.
3. Rebuild the dimension right-click menu around a saved-sizes list with Add/Del.

## Decisions

| Question | Decision |
|---|---|
| Add… input | One inputbox, comma-separated values: `45, 200, 400` |
| Del… | Submenu listing each value; click deletes it. Plus `Delete all` |
| VCB trigger | Left-click the dimension text locks it; type + Enter applies; Esc cancels |
| Dims Manager | Code kept, only the `Show Manager` menu item removed |
| Referenced Dimensions, gray headers, x0.5/x2 suggestions | Removed — menu matches the mockup exactly |
| UI Scale Factor submenu | Deleted, not relocated (see below) |

`UI Scale Factor` and `verify_ui_scale` exist only to scale the radial menu: every
consumer of `SCALE_FACTOR` lives under `radial_menu/`. Once the pet toolbar is gone
they control nothing, so they go with it. Dimension text sizing is independent —
it uses `view.pixels_to_model(20, point)`.

## Structure

```
htu_scaleplus/
  dim_favorites.rb   NEW  read/write the saved-size list on object attributes
  dim_menu.rb        NEW  build the dimension right-click menu
  scale_tool.rb      geometry + drawing + tool lifecycle (~250 lines smaller)
  pet_toolbar.rb     DELETED
  radial_menu/       files kept, require dropped from loader
  dims.rb, ui/       unchanged, just no longer reachable
```

Three call sites write to the saved-size list (Add…, Del…, VCB apply). Without one
owner that logic ends up spread across three places and drifts.

## DimFavorites

Keeps the existing attribute names `lenx_dims` / `leny_dims` / `lenz_dims` and the
existing dual write to both instance and definition, so saved data survives.

```ruby
DimFavorites.list(object, axis)           # -> [Length], sorted, [] when unset
DimFavorites.add(object, axis, values)    # merge, dedupe, sort, save
DimFavorites.remove(object, axis, value)
DimFavorites.clear(object, axis)
DimFavorites.parse(text)                  # -> [[Length], [bad strings]]
```

`parse` splits on commas, strips, drops empties, converts with `String#to_l` so it
follows the model's current units.

**Error rule: if any entry is invalid, nothing is added.** A `UI.messagebox` lists
exactly which strings failed. Partial adds leave the user unsure what landed.
Values `<= 0` count as invalid.

## DimMenu

```
45 mm                  <- checkmark when equal to the current length
200 mm
400 mm
──────────────
Add...
Del          >    45 mm / 200 mm / 400 mm / --- / Delete all
Text size    >    Small / Medium / Large
```

- The list, Add… and Del… all act on the axis of the dimension that was clicked.
- Empty list: the top section is empty and `Del >` is omitted entirely, since an
  empty submenu reads as broken.
- Clicking a value keeps the existing sequence: `start_operation` → `set_dim_value`
  → `commit` → `dc_redraw` → reselect the Scale tool.

## VCB entry

The lock stores the **axis**, not the dim hash. `@data_dims` is rebuilt whenever the
camera moves, so a held hash goes stale and `dim[:line]` would carry old geometry —
orbiting mid-entry would scale by the wrong amount. `set_dim(axis, value)` already
resolves the current dim by axis, so locking the axis reuses it.

A `dim_axis(dim)` helper replaces the `vec.parallel?(@tr_bb.xaxis)` chain currently
duplicated in three places; the menu and the VCB path both need it.

| Event | Behaviour |
|---|---|
| Left-click on dim text | `@locked_axis = dim_axis(dim)`; VCB shows `LenX` + current value; status bar hint. No dialog |
| Left-click elsewhere | Unlock, pop tool |
| Type + Enter | `onUserText` → `String#to_l`. Invalid or `<= 0`: beep, restore the VCB value, **stay locked**. Valid: `start_operation("Resize")` → `set_dim(@locked_axis, value)` → `commit` → unlock → reselect Scale tool |
| Esc | `onCancel` → unlock, clear VCB, pop tool |
| Mouse leaves the dim | While locked the tool no longer pops — the pop condition gains `&& !@locked_axis` |
| Tool change / deactivate | Unlock, clear the VCB label |

Feedback: `draw_dimensions` already outlines the text box when `dim[:hover]`. It
gains the locked-axis condition and a thicker line. No new geometry.

## Pet toolbar removal

Delete `pet_toolbar.rb`. From `scale_tool.rb` remove `place_menu`,
`update_menu_position`, `menu_can_fit?`, `can_fit?`, the `@existing_rects` /
`@new_rects` debug pair, the `@highlight_center` branch in `draw_scale_points`, and
every `@pet_toolbar` reference. From `main.rb` remove `scale_factor=` and
`verify_ui_scale`. From `loader.rb` drop the `pet_toolbar` and `radial_menu`
requires.

The six orphaned commands move to the real toolbar:

```ruby
tb.add_item(cmd)
tb.add_separator
PLUGIN.cmds.each_key { |c| tb.add_item(c) }
```

They already carry icons, tooltips and validation procs, so they work as native
toolbar buttons; the procs gray them out when the selection is not a single
component, which keeps `set_behavior` from dereferencing a nil `sel[0]`.

## Testing

`load_test.rb` and `runtime_test.rb` assert that `PetToolbar` constructs, so both
need updating or `build.rb` blocks the package. Two new tests run under the shim:

- **`DimFavorites.parse`** — pure logic: `"45, 200, 400"` yields three values; a bad
  entry returns it in the failure list and adds nothing; zero and negatives are
  invalid; duplicates collapse.
- **`DimMenu`** — build into a recording fake menu and assert the structure against
  the mockup: N values, separator, `Add...`, `Del >`, `Text size >`, no
  `Show Manager`; and no `Del >` when the list is empty.

Not automatable, must be checked in SketchUp: the real VCB round trip, Esc, and
orbiting while locked.
