module TRINH_VAN_PHUC::HTU_ScalePlus
  # Builds the context menu shown when right-clicking a dimension:
  #
  #   45 mm                 <- the saved sizes, checked when one is the current length
  #   200 mm
  #   ---------
  #   Open list...          add, delete, delete all -- all in one window
  #   Text size  >          Small / Medium / Large
  #
  # With nothing saved, that is the whole menu: Open list... and Text size, no
  # divider above them.
  #
  # One list serves all three axes, but picking a size still applies it to the
  # axis of the dimension that was right-clicked -- which is why the axis is
  # threaded through here.
  #
  # There used to be Add... and a Del submenu as well. Both are gone: the window
  # does each job better, because a native menu closes on the first pick and so
  # every added or deleted value cost a fresh trip through the menu.
  #
  # Four of the original's items are gone by request, not by accident:
  #
  #   "Favorite Dimensions" -- a grayed heading over the first block. The block is
  #   the top of the menu and the sizes are what the menu is for, so the label was
  #   an unclickable row explaining the obvious.
  #
  #   "Show Manager" -- opened the old Vue dimension dialog. "Open list..." above
  #   it does the same job in a window built for it. Nothing else opens DimsUI now,
  #   so that dialog is unreachable while it still ships; observer.rb's calls into
  #   it are no-ops with no dialog to refresh.
  #
  #   The half and double suggestions -- "225 (x0.5)" and "900 (x2.0)", shown only
  #   while nothing was saved. They were a multiplication offered as a size, which
  #   is what dragging a grip already does. Little was lost: a typed size joins the
  #   saved list on its own, so the list fills from the first resize -- only the very
  #   first right-click, before anything has been resized, has nothing on it.
  #
  #   "Referenced Dimensions" and its "(in model)" sizes -- the lengths every other
  #   instance of this definition is already built at. It read well in principle and
  #   badly in practice: the sizes on it are whatever the neighbours happen to have
  #   been dragged to, so the block filled up with values like "~ 592" -- the tilde
  #   being SketchUp saying the number does not even round cleanly. Nobody picks 592
  #   on purpose. The saved list is the curated answer to the same question, and
  #   ScalePPTool#referenced_dims and #same_dc_definition went with it.
  #
  # Everything else here is Curic Scale++ 1.1.2's own menu.
  module DimMenu
    def self.build(menu, tool, object, axis, length)
      values = DimFavorites.list(object, axis)

      if object
        add_value_items(menu, tool, axis, length, values)
        # A separator divides, so it needs a block on both sides. Nothing precedes
        # it on a fresh install now, and a menu that opens with a horizontal rule
        # reads as an item that failed to draw.
        unless values.empty?
          menu.add_separator
        end
        menu.add_item("Open list...") { defer { DimAddDialog.show(object, axis) } }
      end

      add_text_size_submenu(menu)
    end

    # A saved size applies immediately -- one click, no confirmation.
    def self.add_value_items(menu, tool, axis, length, values)
      values.each do |value|
        item = menu.add_item(value.to_s) { tool.apply_dim_value(axis, value) }
        menu.set_validation_proc(item) do
          value == length ? MF_CHECKED : MF_ENABLED
        end
      end
    end

    # #add_heading went with the referenced block. It drew a grayed, unclickable row
    # standing in for a group label, and with one block left there are no groups to
    # label -- the sizes start the menu and a separator ends them.

    def self.add_text_size_submenu(menu)
      submenu = menu.add_submenu("Text size")
      { "Small" => DIM_SMALL, "Medium" => DIM_MEDIUM, "Large" => DIM_LARGE }.each do |label, size|
        item = submenu.add_item(label) do
          PLUGIN.settings[:dim_text_size] = size
          Sketchup.active_model.active_view.invalidate
        end
        submenu.set_validation_proc(item) do
          PLUGIN.settings[:dim_text_size] == size ? MF_CHECKED : MF_ENABLED
        end
      end
    end

    # On Windows a modal dialog opened straight from a menu callback can land
    # behind the SketchUp window; the existing code defers it by a tick to avoid
    # that, and the same workaround applies here.
    def self.defer(&block)
      unless IS_WIN
        return block.call
      end
      id = UI.start_timer(0.1, false) do
        UI.stop_timer(id)
        block.call
      end
    end
  end
end
