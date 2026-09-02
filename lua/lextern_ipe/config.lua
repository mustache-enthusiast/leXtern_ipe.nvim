-- lextern_ipe.nvim configuration
--
-- This is the single source of config for the plugin, applied even if
-- setup() is never called; setup(opts) overrides these on top. Since
-- lextern_ipe.nvim is currently a single-user, single-machine plugin,
-- this file doubles as an actual personal config, not just a schema of
-- generic defaults -- edit it directly rather than passing opts.

local M = {}

M.defaults = {
  -- Directory creation behavior: "ask", "always", "never"
  dir_create_mode = "ask",

  -- Debounce interval for file watcher (ms)
  debounce_ms = 100,

  -- How many levels of \RequirePackage/\usepackage indirection to follow
  -- when resolving whether \incfig is defined by a loaded class/package
  -- via kpsewhich. 1 = only check \documentclass/\usepackage named
  -- directly in the buffer (not what those in turn require). 0 disables
  -- package resolution entirely, falling back to a buffer-text-only
  -- check. See :checkhealth lextern_ipe if kpsewhich isn't found.
  kpsewhich_depth = 1,

  -- Whether :AddFigure/:InsertFigure prompt before auto-inserting the
  -- \incfig preamble when it can't find a definition:
  -- "ask" (prompt every time, default), "always" (insert without
  -- asking), "never" (skip silently -- no prompt, no insert)
  confirm_missing_preamble = "ask",

  -- Whether :DefineIncfig prompts before inserting a second \incfig
  -- definition when one is already found: "ask", "always", "never"
  confirm_duplicate_preamble = "ask",

  -- Reserved for future use: customizing where/how the figures
  -- directory is named and located, instead of the fixed
  -- "<basename>_figures" convention currently hardcoded in
  -- get_figures_dir()/get_figures_reldir() in init.lua. Not yet
  -- consumed by the plugin.
  -- figures_dir_pattern = "%s_figures",

  -- Optional function(filepath) to launch IPE yourself, e.g. to open it
  -- floating under a tiling WM. Receives the absolute path to the .ipe
  -- file. When nil, IPE is launched as a plain detached job.
  --
  -- ACTIVE: Hyprland floating window, matching the previous built-in
  -- floating=true behavior before it was generalized into this hook.
  -- Assumes hyprctl is on PATH; falls back to a normal (non-floating)
  -- launch if it errors, since jobstart doesn't surface that failure.
  launch_cmd = function(filepath)
    local rules = "[float;size 900 700;center]"
    vim.fn.jobstart(
      { "hyprctl", "dispatch", "exec", rules, "--", "ipe", filepath },
      { detach = true }
    )
  end,

  -- TESTING ONLY -- intentionally broken launch_cmd (calls a binary
  -- that doesn't exist) to exercise :AddFigure/:EditFigure error
  -- handling. FLAGGED FOR REMOVAL once the testing pass covering
  -- launch_cmd is done. To use: comment out the launch_cmd above and
  -- uncomment this one.
  -- launch_cmd = function(filepath)
  --   vim.fn.jobstart(
  --     { "lextern-ipe-intentionally-missing-binary", filepath },
  --     { detach = true }
  --   )
  -- end,
}

return M
