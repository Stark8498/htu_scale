# Curic Scale++ 1.1.2 — plaintext rebuild

A fully plaintext, installable rebuild of Curic Scale++ assembled from the
decompiled AST. The RubyEncoder blob is gone: every line the plugin runs is
readable Ruby, and the `rgloader` native loader is no longer shipped or needed.

Build: `ruby build.rb` → `dist/htu_scaleplus-<version>.rbz`

The 1.1.2 in the title above is the **upstream** version this was rebuilt from. The
rebuild itself is renamed and versioned on its own: currently HTU ScalePlus 1.2.2,
set in one place only — `PLUGIN_VERSION` in `htu_scaleplus.rb`, which is also where
`build.rb` reads the .rbz filename from.

---

## 1. Tree

```
curic_scale_pp_src/
├── build.rb                     # verify + package; refuses to build if a test fails
├── README_BUILD.md              # this file
├── dist/
│   └── htu_scaleplus-1.2.2.rbz  # 56 files, ~473 KB
├── test/                        # not shipped in the .rbz
│   ├── su_shim.rb               # SketchUp API shim (load harness)
│   ├── load_test.rb             # loads the plugin end to end
│   ├── runtime_test.rb          # fires startup timers, builds tool + pet toolbar
│   └── dropped_param_scan.rb    # Ripper scan for lost method parameters
│
├── curic_scale_pp.rb            # extension registration (SketchUp reads this)
└── curic_scale_pp/
    ├── loader.rb                # init + create_menu  ← was the encrypted blob
    ├── utils.rb main.rb pet_toolbar.rb radial_menu.rb
    ├── tool.rb scale_tool.rb dims.rb observer.rb overlay.rb
    ├── licensing.rb license_ui.rb
    ├── radial_menu/
    │   ├── constants.rb shape_geom.rb menu.rb item.rb layout.rb
    │   ├── circle_layout.rb rectangle_layout.rb command.rb sub_menu.rb
    │   ├── label_text.rb tooltip.rb listbox.rb
    │   ├── viewui/{item,slider,ui}.rb
    │   └── Resources/{missing,text_command,tb_unknown}.png
    ├── Resources/               # 13 icons (icon.svg/pdf, icon_x/y/z/xyz, reset, …)
    ├── ui/{html,css,js}/        # dims dialog: Vue + Element UI
    └── SF Pro Rounded_Bold{,2}.json
```

The archive layout is the SketchUp standard and matches the original exactly:
`curic_scale_pp.rb` at the archive **root**, support files in the same-named
folder beside it. No `require` paths were rewritten — every file already used
`Sketchup.require "#{PATH}/…"` against the constants defined in the root file,
so the original structure was kept rather than reshuffled into `lib/`. Moving
files would have broken `PATH_R`, `DimsUI`'s `ui/` lookup and the `__dir__`
typeface load for no gain.

## 2. Load order

`curic_scale_pp.rb` defines `PLUGIN*`, `PATH`, `PATH_ROOT` and registers the
extension, pointing `SketchupExtension` at `curic_scale_pp/loader`. `loader.rb`
then pulls the rest in dependency order:

```
utils → main → pet_toolbar → radial_menu → tool → scale_tool
      → dims → observer → overlay → licensing → license_ui
```

…then creates the `Curic ▸ Scale++` submenus, the toolbar command, the six
behaviour commands, and the `ScalePP2Observer`.

## 3. Changes from the shipped original

### Removed (2 items, both RubyEncoder-only)

| File | Why |
|------|-----|
| `curic_scale_pp/rgloader/**` (11 files) | The native RubyEncoder loader. Nothing left in the tree calls `RGLoader_load`. |
| `curic_scale_pp/load_rubyencoder_helper.rb` | Pops a *"Curic Load Error — Missing RubyEncoder"* dialog 10 s after startup when `RGLoader` is undefined. In a plaintext build that is always, so the require was dropped from `curic_scale_pp.rb`. |
| `curic_scale_pp/curic_scale_pp.susig` | Trimble's signature hashes every shipped file; it cannot validate against modified sources, and an invalid signature reads as *tampered*. Ships unsigned — see §6. |

`licensing.rb` still calls `RGLoader.get_mac_addresses` / `get_machine_id`, but
both are already wrapped in `defined?(RGLoader) &&` with a manual-detection
fallback, so licensing works unchanged without the loader.

### Fixed — decompiler defects (3)

| File | Defect | Fix |
|------|--------|-----|
| `radial_menu/shape_geom.rb` | `rectangle_points(origin = ORIGIN)` — the AST lost two optional params. The body uses bare `width`/`height`, and the only caller, `square_points`, invokes it with **three** arguments → `ArgumentError` on every pet-toolbar draw. | `rectangle_points(origin = ORIGIN, width = 1, height = 1)` |
| `utils.rb` | `rescue StandardError => e` followed by `p(exception)` → `NameError` raised *out of its own handler*. `Update.check(true)` runs on a 10 s startup timer, so any failed update check crashed. | `p(e)` |
| `radial_menu/command.rb` | `initialize(command = nil, &block)` lost its `data` param; `@data.merge!(data)` then resolved `data` to the attr_reader and self-merged — a no-op by accident only. | `initialize(command = nil, data = {}, &block)` |

### Fixed — upstream defects in the original (2)

These are the **author's** bugs, faithfully decompiled, not AST damage.

| File | Defect | Fix |
|------|--------|-----|
| `radial_menu/menu.rb` | `def missing_method(method, *_args)` is not a Ruby hook — the name is a typo for `method_missing`, and the debug string *inside the method also reads "missing_method"*, which is how we know the AST is faithful. Consequence: the bare `onSetCursor` call in `onMouseMove` raised `NoMethodError` on every hover and aborted the rest of the callback, including `view.invalidate`. | `alias_method :method_missing, :missing_method` (one line; delete it for byte-faithful behaviour) |
| `radial_menu/command.rb` | `center_screen` returns a bare `[x, y]` Array, but `redraw_tooltip` called `center_screen.x` and `center_screen.vector_to(…)`. Fired for every pet-toolbar command, which is constructed *before* being added to a menu, so `menu` is nil there. Swallowed by the method's own `rescue`. | `center_screen[0]` and `Geom::Point3d.new(center_screen)` — the same normalisation `Menu#show` already applies to this Array |

### Reconstructed (1)

`loader.rb` line ~99: `ex = Sketchup.extensions["Curic Behavior"]; if ex && ex.load_on_start?` has an **empty body in the captured AST**. It is an interop hook for the separate *Curic Behavior* extension; an empty branch is a no-op, and there is nothing in the capture to reconstruct it from. Left empty and commented.

Also in `loader.rb`: the SketchUp-< 23 guard called `PLUGIN.load_on_start?`, which nothing defines — it would have raised `NoMethodError`. `load_on_start?` and `uncheck` are a `SketchupExtension` pair, so the receiver is `PLUGIN_EX`. Dead path on SketchUp 23+.

### Dead code kept (4 files)

`radial_menu/listbox.rb` and `radial_menu/viewui/{item,slider,ui}.rb` are never
required — nothing references `Listbox` or `ViewUI`. `viewui/ui.rb` even
requires `button`, `checkbox` and `toggle`, which **do not exist in the original
`.rbz` either**; `Sketchup.require` returns `false` for a missing file instead of
raising, so this was always inert. Shipped anyway to match the original.

## 4. Verification

`build.rb` runs all four gates and aborts the package on any failure.

| Gate | Result |
|------|--------|
| `ruby -c` on every `.rb` | 32/32 Syntax OK |
| `test/dropped_param_scan.rb` | PASS — no unresolvable bare identifier |
| `test/load_test.rb` | PASS — 24 files load; toolbar, both menus, 7 commands, observer, settings all wired; 15 referenced resources present |
| `test/runtime_test.rb` | PASS — both startup timers fire clean; 6 behaviour commands + icons; `ScalePP2Overlay`, `ScalePPTool`, `PetToolbar`, `RadialMenu::Menu`, `ScalePP2Observer` all construct; **0 exceptions swallowed** |

Run them individually with `ruby test/<name>.rb`.

`runtime_test.rb` monkey-patches `Kernel#p` so that exceptions caught by the
plugin's own `rescue => e; p(e)` blocks are reported as failures instead of
scrolling past as console noise. That is how the two upstream defects above
were found.

### What the harness does *not* prove

`test/su_shim.rb` is a **load** harness, not a behaviour harness: it returns
plausible shapes, it does not model SketchUp semantics. `Geom::Transformation`
is a stub with no matrix arithmetic, so none of the actual scaling maths is
exercised. Two shim methods — `UI::Command#proc` and `#get_validation_proc`,
both used by `pet_toolbar.rb` — are not in the published SketchUp API docs and
could not be verified from here; they are assumed present because the original
plugin ships and works. Scale correctness must be checked in SketchUp.

## 5. Install

1. `ruby build.rb`
2. SketchUp → **Extensions ▸ Extension Manager ▸ Install Extension…**
3. Pick `dist/htu_scaleplus-1.2.2.rbz`
4. Restart SketchUp.

To package by hand instead: zip the contents of this folder **excluding**
`test/`, `dist/`, `build.rb` and `README_BUILD.md`, so that `curic_scale_pp.rb`
sits at the archive root, then rename `.zip` → `.rbz`. Do not zip the folder
itself — an extra wrapper directory makes SketchUp reject the archive.

Requires SketchUp 2023 or newer (`loader.rb` enforces this; the plugin uses the
`Sketchup::Overlay` API added in 2023).

## 6. Signing, and what the build does and does not guarantee

The build ships **unsigned**. Set Extension Manager → gear icon → *Security* to
**Unrestricted** or *Approve unidentified extensions*, otherwise SketchUp will
refuse to load it. To sign it, upload the `.rbz` to the Trimble Extension Digital
Signature service; it returns a signed archive with a fresh `.susig`. Signing is
the one step that cannot be done from this repository — it needs a Trimble account
and their service, so the archive is handed over unsigned by design.

Three gates exist specifically so the archive can be handed to a store without a
reviewer finding something the build could have caught:

| Gate | What it refuses to package |
|------|----------------------------|
| `ruby -c` | any shipped file that does not parse |
| `ruby -w` | any **shipped** file with a parse-time warning — unused variable, shadowed name, void assignment. Test files are exempt: a warning there is nobody's problem. This found six, four of them in never-loaded `radial_menu/` |
| archive layout | any archive whose top level is not exactly `htu_scaleplus.rb` + `htu_scaleplus/`. `lib/` and `resources/` had been riding along at the root for four versions, making four top-level entries where two are allowed |

What none of them prove: **nothing here has run inside SketchUp.** Every test runs
against `test/su_shim.rb`. `ruby -w -c` is parse-time only, so a warning SketchUp
itself emits at runtime — a deprecated API call, for instance — is outside what this
can see. Load the `.rbz` and watch the Ruby Console before submitting.

## 7. Sanity check after install

Paste into **Window ▸ Ruby Console**:

```ruby
m = CURIC::ScalePlusPlus
puts "version   : #{m::PLUGIN_VERSION}"
puts "path ok   : #{File.directory?(m::PATH)}"
puts "loaded    : #{$LOADED_FEATURES.count { |f| f.include?('curic_scale_pp') }} files"
puts "observer  : #{m.observer.class}"
puts "commands  : #{m.cmds.size}"
puts "overlay   : #{m.active_overlay.inspect}"
puts "RGLoader  : #{defined?(RGLoader) ? 'present (unexpected)' : 'absent (correct)'}"
```

Expect 24 files, `ScalePP2Observer`, 6 commands, and `RGLoader absent`. Then
check the toolbar appears, `Tools ▸ Curic ▸ Scale++` toggles the overlay, and
`Plugins ▸ Curic ▸ Scale++ ▸ License` opens the dialog.
