local M = {}

-- ============================================================
-- Configuration
-- ============================================================

local defaults = require("lextern_ipe.config").defaults

-- Applied even before setup() is called; see lua/lextern_ipe/config.lua
M.config = defaults

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
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

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

--- Whether a line looks like a definition of \incfig (as opposed to a
--- usage, e.g. \incfig{foo}{caption})
local function line_defines_incfig(line)
  if not line:find("\\incfig", 1, true) then
    return false
  end
  return line:find("\\newcommand", 1, true) ~= nil
    or line:find("\\renewcommand", 1, true) ~= nil
    or line:find("\\providecommand", 1, true) ~= nil
    or line:find("\\def\\incfig", 1, true) ~= nil
    or line:find("DeclareRobustCommand", 1, true) ~= nil
    or line:find("NewDocumentCommand", 1, true) ~= nil
end

--- Check whether the current buffer already defines \incfig
local function has_incfig_defined()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if line_defines_incfig(line) then
      return true
    end
  end
  return false
end

--- Extract the comma-separated argument names from a
--- "\command[options]{name1,name2}" invocation on a line
local function extract_arg_names(line, command)
  local idx = line:find("\\" .. command, 1, true)
  if not idx then
    return {}
  end
  local rest = line:sub(idx + 1 + #command)
  if rest:match("^%s*%[") then
    local _, close = rest:find("%b[]")
    if close then
      rest = rest:sub(close + 1)
    end
  end
  local braces = rest:match("^%s*{([^}]*)}")
  if not braces then
    return {}
  end
  local names = {}
  for name in braces:gmatch("[^,%s]+") do
    table.insert(names, name)
  end
  return names
end

--- Read a file into a list of lines, or nil if it can't be read
local function read_file_lines(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*all")
  f:close()
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

--- Whether any line in a list defines \incfig
local function lines_define_incfig(lines)
  for _, line in ipairs(lines) do
    if line_defines_incfig(line) then
      return true
    end
  end
  return false
end

--- Extract .cls/.sty candidate filenames referenced by \documentclass,
--- \usepackage, and \RequirePackage across a list of lines
local function package_filenames(lines)
  local names = {}
  for _, line in ipairs(lines) do
    for _, name in ipairs(extract_arg_names(line, "documentclass")) do
      table.insert(names, name .. ".cls")
    end
    for _, name in ipairs(extract_arg_names(line, "usepackage")) do
      table.insert(names, name .. ".sty")
    end
    for _, name in ipairs(extract_arg_names(line, "RequirePackage")) do
      table.insert(names, name .. ".sty")
    end
  end
  return names
end

--- Check whether \incfig is defined by a \documentclass or \usepackage
--- the buffer loads, resolving names to files via kpsewhich and
--- scanning them, following \RequirePackage/\usepackage indirection up
--- to config.kpsewhich_depth levels deep (1 = only what the buffer
--- names directly). Returns false if kpsewhich isn't on PATH, or
--- kpsewhich_depth <= 0, rather than erroring.
local function has_incfig_in_loaded_packages()
  local depth = M.config.kpsewhich_depth or 1
  if depth <= 0 or not has_command("kpsewhich") then
    return false
  end

  local visited = {}
  local queue = package_filenames(vim.api.nvim_buf_get_lines(0, 0, -1, false))

  for level = 1, depth do
    local next_queue = {}
    for _, filename in ipairs(queue) do
      if not visited[filename] then
        visited[filename] = true
        local output = vim.fn.system({ "kpsewhich", filename })
        if vim.v.shell_error == 0 then
          local path = vim.trim(output)
          if path ~= "" then
            local lines = read_file_lines(path)
            if lines then
              if lines_define_incfig(lines) then
                return true
              end
              if level < depth then
                vim.list_extend(next_queue, package_filenames(lines))
              end
            end
          end
        end
      end
    end
    queue = next_queue
    if #queue == 0 then
      break
    end
  end

  return false
end

--- Check whether \incfig is defined, in the buffer or in a loaded
--- class/package. Caches a positive result on the buffer so repeated
--- calls (e.g. across several :AddFigure invocations) don't re-shell
--- out to kpsewhich every time.
local function incfig_is_defined()
  if vim.b.lextern_ipe_incfig_defined then
    return true
  end
  local found = has_incfig_defined() or has_incfig_in_loaded_packages()
  if found then
    vim.b.lextern_ipe_incfig_defined = true
  end
  return found
end

--- Find the 1-based line number of the last \usepackage line in the
--- current buffer, or nil if there isn't one
local function find_last_usepackage_line()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local last = nil
  for i, line in ipairs(lines) do
    if line:find("\\usepackage", 1, true) then
      last = i
    end
  end
  return last
end

--- Read a template file's contents, trimming a trailing newline
--- Returns the content string, or nil + error message
local function read_template(name)
  local path = plugin_root() .. "/templates/" .. name
  local f = io.open(path, "r")
  if not f then
    return nil, "Template not found: " .. path
  end
  local content = f:read("*all")
  f:close()
  return (content:gsub("\n+$", ""))
end

--- Warn and offer to insert the \incfig preamble if it doesn't appear
--- to be defined yet (checking the buffer and any resolvable loaded
--- class/package). This is still a heuristic -- e.g. a package that
--- itself requires another package defining \incfig won't be found --
--- so declining is a legitimate choice, not just a dismissal. Governed
--- by config.confirm_missing_preamble ("ask"/"always"/"never").
local function ensure_incfig_preamble()
  if incfig_is_defined() then
    return
  end

  local mode = M.config.confirm_missing_preamble
  if mode == "never" then
    return
  end
  if mode == "always" then
    M.define_incfig(false)
    return
  end

  local response = vim.fn.confirm(
    "\\incfig does not appear to be defined (checked buffer and loaded packages).\n\nInsert the preamble now?",
    "&Yes\n&No", 1
  )
  if response == 1 then
    M.define_incfig(false)
  end
end

-- ============================================================
-- User prompts
-- ============================================================

--- Prompt for text input. Calls callback(result) with the entered
--- string, or callback(nil) if cancelled/empty.
local function ui_input(prompt, callback)
  vim.ui.input({ prompt = prompt .. ": " }, function(result)
    if not result or vim.trim(result) == "" then
      callback(nil)
      return
    end
    callback(vim.trim(result))
  end)
end

--- Select from a list. Calls callback(item) with the chosen item,
--- or callback(nil) if cancelled.
local function ui_select(items, prompt, callback)
  vim.ui.select(items, { prompt = prompt }, function(choice)
    callback(choice)
  end)
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

  if M.config.launch_cmd then
    M.config.launch_cmd(filepath)
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
  ui_input("Figure name", function(name)
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

    ensure_incfig_preamble()

    -- Insert \incfig at cursor
    local reldir = get_figures_reldir()
    insert_at_cursor(string.format("\\incfig{%s/%s}{}", reldir, filename))

    open_ipe(ipe_path)
    ensure_watcher()

    vim.notify("Created: " .. filename .. ".ipe", vim.log.levels.INFO)
  end)
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

  ui_select(figures, "Edit figure", function(selected)
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
  end)
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

  ui_select(figures, "Insert figure", function(selected)
    if not selected then
      return
    end

    ensure_incfig_preamble()

    local reldir = get_figures_reldir()
    insert_at_cursor(string.format("\\incfig{%s/%s}{}", reldir, selected))
  end)
end

--- Insert the \incfig preamble. By default it's placed right after the
--- last \usepackage line (falling back to cursor position if none is
--- found); pass at_cursor=true to always insert at the cursor instead.
function M.define_incfig(at_cursor)
  if incfig_is_defined() then
    local mode = M.config.confirm_duplicate_preamble
    if mode == "never" then
      return
    end
    if mode ~= "always" then
      local response = vim.fn.confirm(
        "\\incfig already appears to be defined (buffer or loaded packages).\n\nInsert anyway?",
        "&Yes\n&No", 2
      )
      if response ~= 1 then
        return
      end
    end
  end

  local content, err = read_template("incfig.tex")
  if not content then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if at_cursor then
    insert_at_cursor(content)
    return
  end

  local anchor = find_last_usepackage_line()
  if not anchor then
    vim.notify("No \\usepackage line found; inserting at cursor instead.", vim.log.levels.INFO)
    insert_at_cursor(content)
    return
  end

  vim.api.nvim_buf_set_lines(0, anchor, anchor, false, vim.split(content, "\n", { plain = true }))
end

return M
