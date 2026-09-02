-- leXtern_ipe.nvim command registration
-- This file is auto-loaded by Neovim from the plugin/ directory

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

-- :AddFigure targets the current file's own figures dir; :AddFigure!
-- targets the shared library dir instead.
cmd("AddFigure", function(opts)
  require("lextern_ipe").create_figure(opts.bang)
end, { bang = true })

-- :DefineIncfig inserts \usepackage{lextern-ipe} after the last
-- \usepackage line (or \documentclass, or cursor, as fallbacks);
-- :DefineIncfig! always inserts at the cursor.
cmd("DefineIncfig", function(opts)
  require("lextern_ipe").define_incfig(opts.bang)
end, { bang = true })

cmd("EditFigure", function(opts)
  require("lextern_ipe").edit_figure(opts.bang)
end, { bang = true })

cmd("InsertFigure", function(opts)
  require("lextern_ipe").insert_figure(opts.bang)
end, { bang = true })

cmd("StartWatcher", function()
  require("lextern_ipe").start_watcher()
end)

-- :StopWatcher stops every active watcher (per-file and library alike).
cmd("StopWatcher", function()
  require("lextern_ipe").stop_watcher()
end)

cmd("WatcherStatus", function()
  require("lextern_ipe").watcher_status()
end)
