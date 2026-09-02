-- leXtern_ipe.nvim command registration
-- This file is auto-loaded by Neovim from the plugin/ directory

--- Parse recognized boolean flags out of a command's fargs. Returns a
--- table of flag -> boolean; warns (but doesn't block) on anything
--- unrecognized.
local function parse_flags(name, fargs, recognized)
  local result = {}
  for _, flag in ipairs(recognized) do
    result[flag] = false
  end
  for _, arg in ipairs(fargs) do
    if result[arg] == nil then
      vim.notify(name .. ": unrecognized argument: " .. arg, vim.log.levels.WARN)
    else
      result[arg] = true
    end
  end
  return result
end

--- Completion function offering `flags` that start with what's been
--- typed so far (Neovim doesn't filter Lua completion results itself)
local function flag_complete(flags)
  return function(arglead)
    return vim.tbl_filter(function(flag)
      return flag:sub(1, #arglead) == arglead
    end, flags)
  end
end

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

-- :AddFigure targets the current file's own figures dir; :AddFigure
-- --lib targets the shared library dir instead.
cmd("AddFigure", function(opts)
  local flags = parse_flags("AddFigure", opts.fargs, { "--lib" })
  require("lextern_ipe").create_figure(flags["--lib"])
end, { nargs = "*", complete = flag_complete({ "--lib" }) })

-- :DefineIncfig inserts \usepackage{lextern-ipe} after the last
-- \usepackage line (or \documentclass, or cursor, as fallbacks);
-- :DefineIncfig --cursor always inserts at the cursor.
cmd("DefineIncfig", function(opts)
  local flags = parse_flags("DefineIncfig", opts.fargs, { "--cursor" })
  require("lextern_ipe").define_incfig(flags["--cursor"])
end, { nargs = "*", complete = flag_complete({ "--cursor" }) })

cmd("EditFigure", function(opts)
  local flags = parse_flags("EditFigure", opts.fargs, { "--lib" })
  require("lextern_ipe").edit_figure(flags["--lib"])
end, { nargs = "*", complete = flag_complete({ "--lib" }) })

cmd("InsertFigure", function(opts)
  local flags = parse_flags("InsertFigure", opts.fargs, { "--lib" })
  require("lextern_ipe").insert_figure(flags["--lib"])
end, { nargs = "*", complete = flag_complete({ "--lib" }) })

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
