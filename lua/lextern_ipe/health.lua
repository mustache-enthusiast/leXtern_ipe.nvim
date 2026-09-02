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

--- Report on whether config[key] is one of "ask"/"always"/"never"
local function check_ask_always_never(config, key)
  local value = config[key]
  if value == "ask" or value == "always" or value == "never" then
    vim.health.ok(key .. " = " .. value)
  else
    vim.health.error(key .. " is invalid: " .. tostring(value), { 'Expected "ask", "always", or "never"' })
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
  for _, name in ipairs({ "template.ipe", "lextern-ipe.sty", "preamble.isy" }) do
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

  -- Unknown option names are otherwise silently ignored, so a typo or
  -- an option from an older version (e.g. float_width) does nothing
  -- and nobody finds out.
  local known = vim.deepcopy(lextern_ipe.defaults)
  known.launch_cmd = true -- defaults to nil, so absent from `defaults`
  local unknown = {}
  for key in pairs(config) do
    if known[key] == nil then
      table.insert(unknown, key)
    end
  end
  table.sort(unknown)
  if #unknown > 0 then
    vim.health.warn("unrecognized config option(s), ignored: " .. table.concat(unknown, ", "), {
      "Check the option names against the README's setup() example.",
    })
  else
    vim.health.ok("all config option names recognized")
  end

  check_ask_always_never(config, "dir_create_mode")
  check_ask_always_never(config, "confirm_missing_preamble")
  check_ask_always_never(config, "confirm_duplicate_preamble")
  check_ask_always_never(config, "confirm_missing_library_package")

  if type(config.library_dir) == "string" and config.library_dir ~= "" then
    local resolved = lextern_ipe.library_dir()
    -- The path is baked into the .sty and used inside \includegraphics,
    -- where these characters are all special to LaTeX.
    local bad = resolved:match("[%s#%%~]")
    if bad then
      vim.health.error(
        string.format("library_dir contains %s, which LaTeX can't use in a file path: %s", vim.inspect(bad), resolved),
        { "Pick a library_dir without spaces, #, %, or ~ (after expansion)." }
      )
    elseif resolved ~= config.library_dir then
      vim.health.ok("library_dir = " .. config.library_dir .. " (resolves to " .. resolved .. ")")
    else
      vim.health.ok("library_dir = " .. resolved)
    end
  else
    vim.health.error("library_dir should be a non-empty string, got: " .. tostring(config.library_dir))
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

  if type(config.floating) ~= "boolean" then
    vim.health.error("floating should be true or false, got: " .. tostring(config.floating))
  end
  local size = config.float_size
  if type(size) ~= "table" or type(size[1]) ~= "number" or type(size[2]) ~= "number" or size[1] < 1 or size[2] < 1 then
    vim.health.error("float_size should be { width, height } in pixels, got: " .. vim.inspect(size))
  end

  if config.launch_cmd ~= nil and type(config.launch_cmd) ~= "function" then
    vim.health.error("launch_cmd should be a function or nil, got: " .. type(config.launch_cmd))
  elseif config.launch_cmd then
    if config.floating then
      vim.health.warn("both launch_cmd and floating=true are set; launch_cmd takes precedence")
    else
      vim.health.ok("launch_cmd is set to a custom function")
    end
  elseif config.floating then
    local hyprland = require("lextern_ipe.hyprland")
    if hyprland.is_available() then
      -- `hyprctl eval` only ever prints "ok", so the version comes from
      -- `hyprctl version` ("Hyprland 0.56.2 built from ...")
      local version = vim.fn.system({ "hyprctl", "version" }):match("Hyprland%s+(%S+)") or "unknown version"
      vim.health.ok(
        string.format("floating=true: Ipe opens as a %dx%d centered floating window via hyprctl eval (Hyprland %s)",
          size[1], size[2], version)
      )
    else
      vim.health.warn("floating=true but Hyprland isn't detected (needs hyprctl on PATH and HYPRLAND_INSTANCE_SIGNATURE)", {
        "Ipe will open normally. For other compositors, use launch_cmd instead.",
      })
    end
  else
    vim.health.info("floating=false and launch_cmd not set; IPE is launched as a plain detached job")
  end

  vim.health.start("lextern_ipe.nvim: library package")
  local expected_pkg = vim.fn.stdpath("data") .. "/lextern_ipe/lextern-ipe.sty"
  if vim.fn.filereadable(expected_pkg) == 0 then
    vim.health.warn(
      "Generated package not found: " .. expected_pkg,
      { "Call require('lextern_ipe').setup() (or restart Neovim) to generate it." }
    )
  elseif vim.fn.executable("kpsewhich") == 0 then
    vim.health.info(
      "Package generated at " .. expected_pkg .. "; can't verify TEXINPUTS without kpsewhich"
    )
  else
    local output = vim.fn.system({ "kpsewhich", "lextern-ipe.sty" })
    local resolved = vim.v.shell_error == 0 and vim.trim(output) or ""
    if resolved == expected_pkg then
      vim.health.ok("TEXINPUTS is set up correctly (kpsewhich finds " .. expected_pkg .. ")")
    elseif resolved ~= "" then
      vim.health.warn("kpsewhich found a different lextern-ipe.sty than expected", {
        "Expected: " .. expected_pkg,
        "Found: " .. resolved,
      })
    else
      vim.health.warn("\\usepackage{lextern-ipe} will not be found by LaTeX -- TEXINPUTS isn't set up", {
        "Add this directory to TEXINPUTS in your shell profile:",
        'export TEXINPUTS="' .. vim.fn.stdpath("data") .. '/lextern_ipe//:$TEXINPUTS"',
        "(This checks Neovim's own environment. If you start Neovim from a desktop launcher"
          .. " rather than a shell, it may not see your profile even though latexmk in a terminal does.)",
      })
    end
  end

  vim.health.start("lextern_ipe.nvim: figure stylesheets")
  local sheets = config.stylesheets
  if type(sheets) ~= "table" then
    vim.health.error("stylesheets should be a list of .isy paths, got: " .. type(sheets))
  elseif #sheets == 0 then
    vim.health.info(
      "stylesheets is empty; new figures get only Ipe's basic stylesheet"
        .. " (see the README's \"Figure stylesheets\" section to give figures your document's fonts/macros)"
    )
  else
    for _, sheet in ipairs(sheets) do
      local path = vim.fn.expand(sheet)
      if vim.fn.filereadable(path) == 0 then
        vim.health.error("stylesheet not readable: " .. path)
      else
        local f = io.open(path, "r")
        local head = f and f:read(4096) or ""
        if f then
          f:close()
        end
        if head:find("<ipestyle", 1, true) then
          vim.health.ok("stylesheet found: " .. path)
        else
          vim.health.error("not an Ipe stylesheet (no <ipestyle> element): " .. path)
        end
      end
    end
  end

  -- Ipe reads IPESTYLES as a colon-separated list of *directories*
  -- that replaces its default style search path; pointing it at a
  -- file (an old recommendation of this README) breaks Ipe's own
  -- "basic" lookup for new documents and does nothing for figures.
  local ipestyles = vim.env.IPESTYLES
  if ipestyles then
    for entry in ipestyles:gmatch("[^:]+") do
      if entry ~= "_" and vim.fn.isdirectory(entry) == 0 then
        vim.health.warn("IPESTYLES entry is not a directory: " .. entry, {
          "Ipe treats IPESTYLES as a colon-separated list of style *directories*, not a stylesheet file.",
          "To give figures a preamble, use the stylesheets config option instead (see README).",
        })
      end
    end
  end
end

return M
