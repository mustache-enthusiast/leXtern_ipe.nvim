local M = {}

-- ============================================================
-- Configuration
-- ============================================================

M.config = {
  -- Directory creation behavior: "ask", "always", "never"
  dir_create_mode = "ask",
  -- Extra flags passed to rofi (e.g. "-theme my-theme")
  rofi_opts = "",
  -- Debounce interval for file watcher (ms)
  debounce_ms = 100,
  -- Open IPE in a floating window (requires Hyprland)
  floating = false,
  -- Floating window dimensions (pixels)
  float_width = 900,
  float_height = 700,
}

-- ============================================================
-- Watcher state
-- ============================================================

M._watcher = {
  watching = false,
  directory = nil,
  handle = nil,
  last_export = {},
}

-- ============================================================
-- Setup
-- ============================================================

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if M._watcher.watching then
        M.stop_watcher()
      end
    end,
  })
end

-- ============================================================
-- Internal utilities
-- ============================================================

--- Resolve the plugin's own root directory (for finding templates)
local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  -- source is <plugin_root>/lua/lextern_ipe/init.lua → go up 3 levels
  return vim.fn.fnamemodify(source, ":h:h:h")
end

--- Convert a figure title to a valid filename
--- "My Cool Figure!" -> "my-cool-figure"
local function sanitize_filename(name)
  local result = name
  result = result:lower()
  result = result:gsub("%s+", "-")
  result = result:gsub("[^%w-]", "")
  result = result:gsub("-+", "-")
  result = result:gsub("^-+", "")
  result = result:gsub("-+$", "")
  if result == "" then
    return nil, "Invalid filename: empty after sanitization"
  end
  return result
end

--- Ensure a directory exists, creating it based on config
--- Returns true or nil + error message
local function ensure_dir(directory)
  if vim.fn.isdirectory(directory) == 1 then
    return true
  end

  local mode = M.config.dir_create_mode

  if mode == "never" then
    return nil, "Directory does not exist: " .. directory
  elseif mode == "always" then
    if vim.fn.mkdir(directory, "p") == 0 then
      return nil, "Failed to create directory: " .. directory
    end
    vim.notify("Created figures directory: " .. directory, vim.log.levels.INFO)
    return true
  elseif mode == "ask" then
    local response = vim.fn.confirm(
      "Figures directory does not exist:\n" .. directory .. "\n\nCreate it?",
      "&Yes\n&No", 1
    )
    if response ~= 1 then
      return nil, "Directory creation cancelled"
    end
    if vim.fn.mkdir(directory, "p") == 0 then
      return nil, "Failed to create directory: " .. directory
    end
    vim.notify("Created figures directory: " .. directory, vim.log.levels.INFO)
    return true
  end

  return nil, "Invalid dir_create_mode: " .. tostring(mode)
end

--- Get the absolute path to the figures directory
--- Derives from current buffer: foo.tex -> foo_figures/
--- Returns absolute path (with trailing slash) or nil + error message
local function get_figures_dir()
  local current = vim.fn.expand("%:p")
  if current == "" then
    return nil, "No file open"
  end

  local dir = vim.fn.fnamemodify(current, ":h")
  local basename = vim.fn.fnamemodify(current, ":t:r")
  local fig_dir = dir .. "/" .. basename .. "_figures/"

  local ok, err = ensure_dir(fig_dir)
  if not ok then
    return nil, err
  end
  return fig_dir
end

--- Get the figures directory name relative to the tex file
--- e.g. "lecture-01_figures"
local function get_figures_reldir()
  local basename = vim.fn.expand("%:t:r")
  if basename == "" then
    return nil, "No file open"
  end
  return basename .. "_figures"
end

--- List .ipe files in a directory, returning basenames without extension
local function list_figures(dir)
  local files = vim.fn.globpath(dir, "*.ipe", false, true)
  local names = {}
  for _, f in ipairs(files) do
    table.insert(names, vim.fn.fnamemodify(f, ":t:r"))
  end
  table.sort(names)
  return names
end

--- Check if a command is available on the system
local function has_command(cmd)
  return vim.fn.executable(cmd) == 1
end

-- ============================================================
-- Rofi integration
-- ============================================================

--- Prompt for text input via rofi
--- Returns the entered string, or nil if cancelled
local function rofi_input(prompt)
  if not has_command("rofi") then
    vim.notify("rofi is not installed", vim.log.levels.ERROR)
    return nil
  end
  local cmd = string.format('rofi -dmenu -p "%s" -lines 0 %s', prompt, M.config.rofi_opts)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  result = vim.trim(result)
  if result == "" then
    return nil
  end
  return result
end

--- Select from a list via rofi
--- Returns the selected item, or nil if cancelled
local function rofi_select(items, prompt)
  if not has_command("rofi") then
    vim.notify("rofi is not installed", vim.log.levels.ERROR)
    return nil
  end
  local input = table.concat(items, "\n")
  local cmd = string.format('rofi -dmenu -i -p "%s" %s', prompt, M.config.rofi_opts)
  local result = vim.fn.system(cmd, input)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  result = vim.trim(result)
  if result == "" then
    return nil
  end
  return result
end

-- ============================================================
-- IPE operations
-- ============================================================

--- Open an .ipe file in IPE (non-blocking)
local function open_ipe(filepath)
  if not has_command("ipe") then
    vim.notify("ipe is not installed", vim.log.levels.ERROR)
    return false
  end

  if M.config.floating then
    if not has_command("hyprctl") then
      vim.notify("floating=true requires Hyprland (hyprctl not found)", vim.log.levels.WARN)
      vim.fn.jobstart({ "ipe", filepath }, { detach = true })
    else
      local rules = string.format("[float;size %d %d;center]",
        M.config.float_width, M.config.float_height)
      vim.fn.system(string.format('hyprctl dispatch exec "%s" -- ipe "%s"', rules, filepath))
    end
  else
    vim.fn.jobstart({ "ipe", filepath }, { detach = true })
  end

  return true
end

--- Export an .ipe file to PDF using ipetoipe
--- Returns true or nil + error message
local function export_to_pdf(ipe_path)
  if not has_command("ipetoipe") then
    return nil, "ipetoipe is not installed"
  end
  local output = vim.fn.system(string.format('ipetoipe -pdf "%s"', ipe_path))
  if vim.v.shell_error ~= 0 then
    return nil, "ipetoipe failed: " .. output
  end
  return true
end

--- Copy the plugin template to create a new .ipe file
--- Returns true or nil + error message
local function create_ipe_from_template(dest_path)
  local template = plugin_root() .. "/templates/template.ipe"
  if vim.fn.filereadable(template) == 0 then
    return nil, "Template not found: " .. template
  end

  -- Read template
  local f = io.open(template, "r")
  if not f then
    return nil, "Cannot read template: " .. template
  end
  local content = f:read("*all")
  f:close()

  -- Write to destination
  f = io.open(dest_path, "w")
  if not f then
    return nil, "Cannot write file: " .. dest_path
  end
  f:write(content)
  f:close()

  return true
end

--- Insert text at cursor position as new lines
local function insert_at_cursor(text)
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_put(lines, "l", true, true)
end

-- ============================================================
-- File watcher
-- ============================================================

local function on_fs_change(err, filename, events)
  if err or not filename then
    return
  end

  if not filename:match("%.ipe$") then
    return
  end

  -- Debounce
  local now = vim.uv.now()
  local last = M._watcher.last_export[filename] or 0
  if now - last < M.config.debounce_ms then
    return
  end
  M._watcher.last_export[filename] = now

  local ipe_path = M._watcher.directory .. "/" .. filename

  vim.schedule(function()
    local ok, export_err = export_to_pdf(ipe_path)
    if ok then
      local pdf_name = filename:gsub("%.ipe$", ".pdf")
      vim.api.nvim_echo({ { pdf_name .. " ✓", "MoreMsg" } }, false, {})
    else
      vim.notify("Export failed: " .. filename .. "\n" .. (export_err or ""), vim.log.levels.ERROR)
    end
  end)
end

--- Silently ensure the watcher is running for the current figures dir
local function ensure_watcher()
  if M._watcher.watching then
    return
  end
  local dir = get_figures_dir()
  if dir then
    M.start_watcher(dir)
  end
end

function M.start_watcher(directory)
  if not directory then
    local err
    directory, err = get_figures_dir()
    if not directory then
      vim.notify(err, vim.log.levels.ERROR)
      return nil
    end
  end

  if vim.fn.isdirectory(directory) == 0 then
    vim.notify("Directory does not exist: " .. directory, vim.log.levels.ERROR)
    return nil
  end

  if M._watcher.watching then
    if M._watcher.directory == directory then
      vim.notify("Already watching: " .. directory, vim.log.levels.INFO)
      return true
    else
      vim.notify("Already watching: " .. M._watcher.directory, vim.log.levels.WARN)
      return nil
    end
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    vim.notify("Failed to create filesystem watcher", vim.log.levels.ERROR)
    return nil
  end

  local ok, watch_err = handle:start(directory, {}, on_fs_change)
  if not ok then
    handle:close()
    vim.notify("Failed to start watcher: " .. (watch_err or "unknown"), vim.log.levels.ERROR)
    return nil
  end

  M._watcher.watching = true
  M._watcher.directory = directory
  M._watcher.handle = handle
  M._watcher.last_export = {}

  vim.notify("Watching: " .. directory, vim.log.levels.INFO)
  return true
end

function M.stop_watcher()
  if not M._watcher.watching then
    vim.notify("Watcher not running", vim.log.levels.INFO)
    return nil
  end

  if M._watcher.handle then
    M._watcher.handle:stop()
    M._watcher.handle:close()
  end

  M._watcher.watching = false
  M._watcher.directory = nil
  M._watcher.handle = nil
  M._watcher.last_export = {}

  vim.notify("Watcher stopped", vim.log.levels.INFO)
  return true
end

function M.watcher_status()
  if not M._watcher.watching then
    vim.notify("Watcher is not running", vim.log.levels.INFO)
  else
    vim.notify(string.format(
      "Watching: %s\nFiles exported: %d",
      M._watcher.directory,
      vim.tbl_count(M._watcher.last_export)
    ), vim.log.levels.INFO)
  end
end

-- ============================================================
-- Commands
-- ============================================================

function M.create_figure()
  local name = rofi_input("Figure name")
  if not name then
    return
  end

  local filename, err = sanitize_filename(name)
  if not filename then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local fig_dir
  fig_dir, err = get_figures_dir()
  if not fig_dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local ipe_path = fig_dir .. filename .. ".ipe"
  if vim.fn.filereadable(ipe_path) == 1 then
    vim.notify("Figure already exists: " .. filename .. ".ipe", vim.log.levels.WARN)
    return
  end

  local ok
  ok, err = create_ipe_from_template(ipe_path)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  -- Insert \incfig at cursor
  local reldir = get_figures_reldir()
  insert_at_cursor(string.format("\\incfig{%s/%s}{}", reldir, filename))

  open_ipe(ipe_path)
  ensure_watcher()

  vim.notify("Created: " .. filename .. ".ipe", vim.log.levels.INFO)
end

function M.edit_figure()
  local fig_dir, err = get_figures_dir()
  if not fig_dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local figures = list_figures(fig_dir)
  if #figures == 0 then
    vim.notify("No figures found in: " .. fig_dir, vim.log.levels.INFO)
    return
  end

  local selected = rofi_select(figures, "Edit figure")
  if not selected then
    return
  end

  local ipe_path = fig_dir .. selected .. ".ipe"
  if vim.fn.filereadable(ipe_path) == 0 then
    vim.notify("File not found: " .. ipe_path, vim.log.levels.ERROR)
    return
  end

  open_ipe(ipe_path)
  ensure_watcher()
end

function M.insert_figure()
  local fig_dir, err = get_figures_dir()
  if not fig_dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local figures = list_figures(fig_dir)
  if #figures == 0 then
    vim.notify("No figures found in: " .. fig_dir, vim.log.levels.INFO)
    return
  end

  local selected = rofi_select(figures, "Insert figure")
  if not selected then
    return
  end

  local reldir = get_figures_reldir()
  insert_at_cursor(string.format("\\incfig{%s/%s}{}", reldir, selected))
end

return M
