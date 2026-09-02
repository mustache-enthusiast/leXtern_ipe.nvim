local M = {}

--- Resolve the plugin's own root directory (for finding templates)
local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  -- source is <plugin_root>/lua/lextern_ipe/health.lua -> go up 3 levels
  return vim.fn.fnamemodify(source, ":h:h:h")
end

--- Report on whether an executable is on PATH
--- opts.required marks this as an error (vs. warning) when missing
--- opts.advice is a string or list of strings shown as follow-up guidance
local function check_executable(name, opts)
  opts = opts or {}
  if vim.fn.executable(name) == 1 then
    vim.health.ok(name .. " found on PATH")
    return
  end
  local msg = name .. " not found on PATH"
  if opts.required then
    vim.health.error(msg, opts.advice)
  else
    vim.health.warn(msg, opts.advice)
  end
end

function M.check()
  vim.health.start("lextern_ipe.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 required")
  end

  check_executable("ipe", {
    required = true,
    advice = { "Required to create and edit figures.", "https://ipe.otfried.org/" },
  })
  check_executable("ipetoipe", {
    required = true,
    advice = { "Required by the file watcher to export figures to PDF on save.", "Ships alongside ipe." },
  })
  check_executable("kpsewhich", {
    required = false,
    advice = {
      "Used to resolve whether \\incfig is defined by a loaded \\documentclass/\\usepackage.",
      "Without it, :AddFigure/:InsertFigure fall back to checking only the current buffer's text,"
        .. " so a custom .cls/.sty that defines \\incfig will trigger the preamble prompt every time.",
    },
  })

  vim.health.start("lextern_ipe.nvim: templates")
  local root = plugin_root()
  for _, name in ipairs({ "template.ipe", "incfig.tex", "preamble.isy" }) do
    local path = root .. "/templates/" .. name
    if vim.fn.filereadable(path) == 1 then
      vim.health.ok("templates/" .. name .. " found")
    else
      vim.health.error("templates/" .. name .. " missing (installation may be corrupt)", { path })
    end
  end

  vim.health.start("lextern_ipe.nvim: config")
  local ok_mod, lextern_ipe = pcall(require, "lextern_ipe")
  if not ok_mod then
    vim.health.error("failed to load lextern_ipe module", { tostring(lextern_ipe) })
    return
  end
  local config = lextern_ipe.config

  local ask_always_never = { ask = true, always = true, never = true }

  if ask_always_never[config.dir_create_mode] then
    vim.health.ok("dir_create_mode = " .. config.dir_create_mode)
  else
    vim.health.error(
      "dir_create_mode is invalid: " .. tostring(config.dir_create_mode),
      { 'Expected "ask", "always", or "never"' }
    )
  end

  if ask_always_never[config.confirm_missing_preamble] then
    vim.health.ok("confirm_missing_preamble = " .. config.confirm_missing_preamble)
  else
    vim.health.error(
      "confirm_missing_preamble is invalid: " .. tostring(config.confirm_missing_preamble),
      { 'Expected "ask", "always", or "never"' }
    )
  end

  if ask_always_never[config.confirm_duplicate_preamble] then
    vim.health.ok("confirm_duplicate_preamble = " .. config.confirm_duplicate_preamble)
  else
    vim.health.error(
      "confirm_duplicate_preamble is invalid: " .. tostring(config.confirm_duplicate_preamble),
      { 'Expected "ask", "always", or "never"' }
    )
  end

  if type(config.debounce_ms) == "number" and config.debounce_ms >= 0 then
    vim.health.ok(string.format("debounce_ms = %d", config.debounce_ms))
  else
    vim.health.error(
      "debounce_ms should be a non-negative number, got: " .. tostring(config.debounce_ms)
    )
  end

  if type(config.kpsewhich_depth) == "number" and config.kpsewhich_depth >= 0 then
    vim.health.ok(string.format("kpsewhich_depth = %d", config.kpsewhich_depth))
  else
    vim.health.error(
      "kpsewhich_depth should be a non-negative number, got: " .. tostring(config.kpsewhich_depth)
    )
  end

  if config.launch_cmd == nil then
    vim.health.info("launch_cmd not set; IPE is launched as a plain detached job")
  elseif type(config.launch_cmd) == "function" then
    vim.health.ok("launch_cmd is set to a custom function")
  else
    vim.health.error("launch_cmd should be a function or nil, got: " .. type(config.launch_cmd))
  end

  vim.health.start("lextern_ipe.nvim: IPE stylesheet")
  local ipestyles = vim.env.IPESTYLES
  if not ipestyles then
    vim.health.info(
      "IPESTYLES not set; figures will render with IPE's basic built-in stylesheet"
        .. " (see templates/preamble.isy for a starter that matches your document fonts/macros)"
    )
  elseif vim.fn.filereadable(ipestyles) == 1 then
    vim.health.ok("IPESTYLES set and readable: " .. ipestyles)
  else
    vim.health.warn("IPESTYLES is set but not readable: " .. ipestyles)
  end
end

return M
