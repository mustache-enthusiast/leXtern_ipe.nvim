-- leXtern_ipe.nvim command registration
-- This file is auto-loaded by Neovim from the plugin/ directory

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

cmd("AddFigure", function()
  require("lextern_ipe").create_figure()
end)

-- :DefineIncfig inserts after the last \usepackage line; :DefineIncfig!
-- inserts at the cursor instead.
cmd("DefineIncfig", function(opts)
  require("lextern_ipe").define_incfig(opts.bang)
end, { bang = true })

cmd("EditFigure", function()
  require("lextern_ipe").edit_figure()
end)

cmd("InsertFigure", function()
  require("lextern_ipe").insert_figure()
end)

cmd("StartWatcher", function()
  require("lextern_ipe").start_watcher()
end)

cmd("StopWatcher", function()
  require("lextern_ipe").stop_watcher()
end)

cmd("WatcherStatus", function()
  require("lextern_ipe").watcher_status()
end)
