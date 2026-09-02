local M = {}

-- Name of the LaTeX package this plugin generates and manages. Providing
-- \incfig (as a fallback -- \providecommand, safe even if \incfig is
-- already defined elsewhere) and \incfiglibrary. Must be discoverable by
-- LaTeX via \usepackage, which requires PACKAGE_DIR (below) to be on
-- TEXINPUTS -- see :checkhealth lextern_ipe.
local PACKAGE_NAME = "lextern-ipe"

-- ============================================================
-- Configuration
-- ============================================================

M.config = {
  -- Directory creation behavior: "ask", "always", "never"
  dir_create_mode = "ask",

  -- Debounce interval for file watcher (ms)
  debounce_ms = 100,

  -- How many levels of \RequirePackage/\usepackage indirection to follow
  -- when resolving whether \incfig (or \usepackage{lextern-ipe}
  -- specifically) is defined by a loaded class/package via kpsewhich.
  -- 1 = only check \documentclass/\usepackage named directly in the
  -- buffer (not what those in turn require). Default 2 so that
  -- \RequirePackage{lextern-ipe} inside a custom \documentclass is
  -- found out of the box (buffer -> class = 1 hop, class -> package =
  -- 2nd hop). 0 disables package resolution entirely, falling back to
  -- a buffer-text-only check. See :checkhealth lextern_ipe if
  -- kpsewhich isn't found.
  kpsewhich_depth = 2,

  -- Whether :AddFigure/:InsertFigure prompt before auto-inserting the
  -- \incfig preamble when it can't find a definition:
  -- "ask" (prompt every time, default), "always" (insert without
  -- asking), "never" (skip silently -- no prompt, no insert)
  confirm_missing_preamble = "ask",

  -- Whether :DefineIncfig prompts before inserting a second \incfig
  -- definition when one is already found: "ask", "always", "never"
  confirm_duplicate_preamble = "ask",

  -- Absolute path to the shared figure library, separate from each
  -- document's own <basename>_figures dir. Created on first use, per
  -- dir_create_mode. Used by :AddFigure!/:EditFigure!/:InsertFigure!.
  -- Baked into the generated lextern-ipe.sty package as \incfiglibrary
  -- (see PACKAGE_NAME below) -- changing this only takes effect for
  -- documents after the next :setup()/Neovim restart regenerates the
  -- package; already-\usepackage{lextern-ipe}'d documents pick it up
  -- automatically at their next compile, no per-document edits needed.
  library_dir = vim.fn.stdpath("data") .. "/lextern_ipe/library",

  -- Whether :AddFigure!/:InsertFigure! prompt before auto-inserting
  -- \usepackage{lextern-ipe} (which provides \incfiglibrary) when it
  -- can't find the package loaded in the buffer: "ask" (default),
  -- "always", "never"
  confirm_missing_library_package = "ask",

  -- Reserved for future use: customizing where/how the figures
  -- directory is named and located, instead of the fixed
  -- "<basename>_figures" convention currently hardcoded in
  -- get_figures_dir()/get_figures_reldir(). Not yet consumed by the
  -- plugin.
  -- figures_dir_pattern = "%s_figures",

  -- Optional function(filepath) to launch IPE yourself, e.g. to open it
  -- floating under a tiling WM. Receives the absolute path to the .ipe
  -- file. When nil, IPE is launched as a plain detached job.
  launch_cmd = nil,
}

-- ============================================================
-- Watcher state
-- ============================================================

--- directory -> { handle = <uv fs_event>, last_export = { [filename] = ms } }
M._watchers = {}

-- ============================================================
-- Internal utilities
-- ============================================================

--- Resolve the plugin's own root directory (for finding templates)
local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  -- source is <plugin_root>/lua/lextern_ipe/init.lua → go up 3 levels
  return vim.fn.fnamemodify(source, ":h:h:h")
end

--- Directory the generated lextern-ipe.sty lives in. Needs to be on
--- TEXINPUTS for \usepackage{lextern-ipe} to find it -- see
--- :checkhealth lextern_ipe.
local function package_dir()
  return vim.fn.stdpath("data") .. "/lextern_ipe"
end

--- (Re)generate <package_dir>/lextern-ipe.sty from
--- templates/lextern-ipe.sty plus the current library_dir. Called from
--- setup(), so the package stays in sync with config across restarts;
--- if you change library_dir at runtime without restarting, call this
--- again (or just re-require("lextern_ipe").setup(...)) to refresh it.
--- Returns true or nil + error message.
local function write_package_file()
  local template = plugin_root() .. "/templates/" .. PACKAGE_NAME .. ".sty"
  local f = io.open(template, "r")
  if not f then
    return nil, "Template not found: " .. template
  end
  local content = f:read("*all")
  f:close()

  local library_dir = (M.config.library_dir or ""):gsub("/+$", "")
  content = content .. string.format("\\newcommand{\\incfiglibrary}{%s}\n", library_dir)

  local dir = package_dir()
  if vim.fn.isdirectory(dir) == 0 and vim.fn.mkdir(dir, "p") == 0 then
    return nil, "Failed to create package directory: " .. dir
  end

  local dest = dir .. "/" .. PACKAGE_NAME .. ".sty"
  f = io.open(dest, "w")
  if not f then
    return nil, "Cannot write package file: " .. dest
  end
  f:write(content)
  f:close()

  return true
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

--- Get the absolute path to the shared figure library, creating it if
--- needed per dir_create_mode. Returns the path (with trailing slash)
--- or nil + error message.
local function get_library_dir()
  local dir = M.config.library_dir
  if dir:sub(-1) ~= "/" then
    dir = dir .. "/"
  end

  local ok, err = ensure_dir(dir)
  if not ok then
    return nil, err
  end
  return dir
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

--- Breadth-first walk of \documentclass/\usepackage/\RequirePackage
--- names starting from `lines`, resolving each via kpsewhich, up to
--- config.kpsewhich_depth levels of further indirection (1 = only what
--- `lines` names directly; each additional level follows one more hop
--- of \RequirePackage/\usepackage inside whatever was just resolved).
--- Calls predicate(stem, file_lines) for every candidate encountered --
--- stem is the filename without its .cls/.sty extension, checked
--- *before* resolving the file (so a predicate that only needs the
--- name, like matching this plugin's own package, doesn't cost a
--- kpsewhich round-trip); file_lines is the resolved file's content on
--- the second call, or nil if it couldn't be resolved/read. Stops and
--- returns true as soon as predicate matches; false if kpsewhich isn't
--- on PATH, kpsewhich_depth <= 0, or nothing matched.
local function walk_kpsewhich_packages(lines, predicate)
  local depth = M.config.kpsewhich_depth or 1
  if depth <= 0 or not has_command("kpsewhich") then
    return false
  end

  local visited = {}
  local queue = package_filenames(lines)

  for level = 1, depth do
    local next_queue = {}
    for _, filename in ipairs(queue) do
      if not visited[filename] then
        visited[filename] = true
        local stem = filename:gsub("%.[^.]*$", "")
        if predicate(stem, nil) then
          return true
        end
        local output = vim.fn.system({ "kpsewhich", filename })
        if vim.v.shell_error == 0 then
          local path = vim.trim(output)
          if path ~= "" then
            local file_lines = read_file_lines(path)
            if file_lines then
              if predicate(stem, file_lines) then
                return true
              end
              if level < depth then
                vim.list_extend(next_queue, package_filenames(file_lines))
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

--- Check whether \incfig is defined by a \documentclass or \usepackage
--- the buffer loads (directly, or transitively through
--- \RequirePackage/\usepackage indirection -- see
--- walk_kpsewhich_packages). Recognizes this plugin's own package by
--- name without needing to read it (we already know what it provides).
local function has_incfig_in_loaded_packages()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return walk_kpsewhich_packages(lines, function(stem, file_lines)
    if stem == PACKAGE_NAME then
      return true
    end
    return file_lines ~= nil and lines_define_incfig(file_lines)
  end)
end

--- Check whether the current buffer loads this plugin's generated
--- lextern-ipe.sty (\usepackage{lextern-ipe}), which provides both
--- \incfig (as a fallback) and \incfiglibrary. Buffer-text only, no
--- kpsewhich -- a fast path for the common case (this plugin inserted
--- \usepackage{lextern-ipe} directly into the buffer) that also works
--- without kpsewhich installed.
local function has_lextern_ipe_package_loaded()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    for _, name in ipairs(extract_arg_names(line, "usepackage")) do
      if name == PACKAGE_NAME then
        return true
      end
    end
  end
  return false
end

--- Check whether \incfig is defined, in the buffer, in a loaded
--- class/package, or via this plugin's own lextern-ipe.sty (loaded
--- directly, or indirectly -- e.g. \RequirePackage{lextern-ipe} inside
--- a custom class file). Caches a positive result on the buffer so
--- repeated calls (e.g. across several :AddFigure invocations) don't
--- re-shell out to kpsewhich every time.
local function incfig_is_defined()
  if vim.b.lextern_ipe_incfig_defined then
    return true
  end
  local found = has_incfig_defined() or has_lextern_ipe_package_loaded() or has_incfig_in_loaded_packages()
  if found then
    vim.b.lextern_ipe_incfig_defined = true
  end
  return found
end

--- Check whether lextern-ipe.sty (and so \incfiglibrary) is loaded, in
--- the buffer directly or transitively (e.g. via a custom class file's
--- own \RequirePackage{lextern-ipe}). Caches a positive result on the
--- buffer.
local function library_package_is_loaded()
  if vim.b.lextern_ipe_library_package_loaded then
    return true
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found = has_lextern_ipe_package_loaded()
    or walk_kpsewhich_packages(lines, function(stem)
      return stem == PACKAGE_NAME
    end)
  if found then
    vim.b.lextern_ipe_library_package_loaded = true
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

--- Find the 1-based line number of the \documentclass line in the
--- current buffer, or nil if there isn't one
local function find_documentclass_line()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find("\\documentclass", 1, true) then
      return i
    end
  end
  return nil
end

--- Insert \usepackage{lextern-ipe} (providing \incfig as a fallback
--- and \incfiglibrary). Placed right after the last \usepackage,
--- falling back to right after \documentclass, falling back to cursor
--- position; pass at_cursor=true to always insert at the cursor
--- instead. No presence/duplicate checks of its own -- callers
--- (M.define_incfig, ensure_library_package) apply their own, distinct
--- checks before calling this.
local function insert_package_usepackage(at_cursor)
  local line = string.format("\\usepackage{%s}", PACKAGE_NAME)

  if at_cursor then
    insert_at_cursor(line)
    return
  end

  local anchor = find_last_usepackage_line() or find_documentclass_line()
  if not anchor then
    vim.notify(
      "No \\usepackage or \\documentclass line found; inserting at cursor instead.",
      vim.log.levels.INFO
    )
    insert_at_cursor(line)
    return
  end

  vim.api.nvim_buf_set_lines(0, anchor, anchor, false, { line })
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

--- Warn and offer to insert \usepackage{lextern-ipe} if it doesn't
--- appear to be loaded yet -- needed for \incfiglibrary specifically.
--- Deliberately narrower than incfig_is_defined(): \incfig might
--- already be available some other way (buffer text, an external
--- class/package), but \incfiglibrary is only ever provided by this
--- package, so it needs its own presence check rather than reusing
--- ensure_incfig_preamble's. Governed by
--- config.confirm_missing_library_package ("ask"/"always"/"never").
local function ensure_library_package()
  if library_package_is_loaded() then
    return
  end

  local mode = M.config.confirm_missing_library_package
  if mode == "never" then
    return
  end
  if mode == "always" then
    insert_package_usepackage(false)
    return
  end

  local response = vim.fn.confirm(
    "\\incfiglibrary isn't available (\\usepackage{lextern-ipe} not found in this buffer).\n\nInsert it now?",
    "&Yes\n&No", 1
  )
  if response == 1 then
    insert_package_usepackage(false)
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

--- Build the fs-event callback for one watched directory. Each
--- watcher gets its own closure so on_fs_change knows which directory
--- (and which watcher's debounce state) it belongs to.
local function on_fs_change(directory)
  return function(err, filename, events)
    if err or not filename then
      return
    end

    if not filename:match("%.ipe$") then
      return
    end

    local watcher = M._watchers[directory]
    if not watcher then
      return
    end

    -- Debounce
    local now = vim.uv.now()
    local last = watcher.last_export[filename] or 0
    if now - last < M.config.debounce_ms then
      return
    end
    watcher.last_export[filename] = now

    local ipe_path = directory .. "/" .. filename

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
end

--- Silently ensure a watcher is running for `directory` (defaults to
--- the current file's own figures dir)
local function ensure_watcher(directory)
  if not directory then
    directory = get_figures_dir()
    if not directory then
      return
    end
  end
  if M._watchers[directory] then
    return
  end
  M.start_watcher(directory)
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

  if M._watchers[directory] then
    vim.notify("Already watching: " .. directory, vim.log.levels.INFO)
    return true
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    vim.notify("Failed to create filesystem watcher", vim.log.levels.ERROR)
    return nil
  end

  local ok, watch_err = handle:start(directory, {}, on_fs_change(directory))
  if not ok then
    handle:close()
    vim.notify("Failed to start watcher: " .. (watch_err or "unknown"), vim.log.levels.ERROR)
    return nil
  end

  M._watchers[directory] = { handle = handle, last_export = {} }

  vim.notify("Watching: " .. directory, vim.log.levels.INFO)
  return true
end

--- Stop a specific watcher (directory), or every active watcher if
--- directory is omitted.
function M.stop_watcher(directory)
  local targets = {}
  if directory then
    if M._watchers[directory] then
      table.insert(targets, directory)
    end
  else
    for dir in pairs(M._watchers) do
      table.insert(targets, dir)
    end
  end

  if #targets == 0 then
    vim.notify("Watcher not running", vim.log.levels.INFO)
    return nil
  end

  table.sort(targets)
  for _, dir in ipairs(targets) do
    local watcher = M._watchers[dir]
    watcher.handle:stop()
    watcher.handle:close()
    M._watchers[dir] = nil
  end

  vim.notify("Watcher stopped: " .. table.concat(targets, ", "), vim.log.levels.INFO)
  return true
end

function M.watcher_status()
  if vim.tbl_isempty(M._watchers) then
    vim.notify("Watcher is not running", vim.log.levels.INFO)
    return
  end

  local lines = {}
  for dir, watcher in pairs(M._watchers) do
    table.insert(lines, string.format("%s (%d exported)", dir, vim.tbl_count(watcher.last_export)))
  end
  table.sort(lines)
  vim.notify("Watching:\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- ============================================================
-- Setup
-- ============================================================

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local ok, err = write_package_file()
  if not ok then
    vim.notify("lextern_ipe: failed to write " .. PACKAGE_NAME .. ".sty: " .. err, vim.log.levels.ERROR)
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if not vim.tbl_isempty(M._watchers) then
        M.stop_watcher()
      end
    end,
  })
end

-- ============================================================
-- Commands
-- ============================================================

--- Get the target directory for a figure command: the shared library
--- (use_library truthy) or the current file's own figures dir.
--- Returns the directory (with trailing slash) or nil + error message.
local function target_dir(use_library)
  if use_library then
    return get_library_dir()
  end
  return get_figures_dir()
end

--- Build the \incfig{...} first argument for a figure in target_dir:
--- \incfiglibrary/name for the library, reldir/name for a per-file
--- figure. Also ensures the relevant preamble/package is present.
local function incfig_arg(use_library, name)
  ensure_incfig_preamble()
  if use_library then
    ensure_library_package()
    return "\\incfiglibrary/" .. name
  end
  return get_figures_reldir() .. "/" .. name
end

function M.create_figure(use_library)
  ui_input("Figure name", function(name)
    if not name then
      return
    end

    local filename, err = sanitize_filename(name)
    if not filename then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    local dir
    dir, err = target_dir(use_library)
    if not dir then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    local ipe_path = dir .. filename .. ".ipe"
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

    insert_at_cursor(string.format("\\incfig{%s}{}", incfig_arg(use_library, filename)))

    open_ipe(ipe_path)
    ensure_watcher(dir)

    vim.notify("Created: " .. filename .. ".ipe", vim.log.levels.INFO)
  end)
end

function M.edit_figure(use_library)
  local dir, err = target_dir(use_library)
  if not dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local figures = list_figures(dir)
  if #figures == 0 then
    vim.notify("No figures found in: " .. dir, vim.log.levels.INFO)
    return
  end

  ui_select(figures, use_library and "Edit library figure" or "Edit figure", function(selected)
    if not selected then
      return
    end

    local ipe_path = dir .. selected .. ".ipe"
    if vim.fn.filereadable(ipe_path) == 0 then
      vim.notify("File not found: " .. ipe_path, vim.log.levels.ERROR)
      return
    end

    open_ipe(ipe_path)
    ensure_watcher(dir)
  end)
end

function M.insert_figure(use_library)
  local dir, err = target_dir(use_library)
  if not dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local figures = list_figures(dir)
  if #figures == 0 then
    vim.notify("No figures found in: " .. dir, vim.log.levels.INFO)
    return
  end

  ui_select(figures, use_library and "Insert library figure" or "Insert figure", function(selected)
    if not selected then
      return
    end

    insert_at_cursor(string.format("\\incfig{%s}{}", incfig_arg(use_library, selected)))
  end)
end

--- Ensure \usepackage{lextern-ipe} is present (providing \incfig as a
--- fallback and \incfiglibrary). By default it's placed right after
--- the last \usepackage line, falling back to right after
--- \documentclass if there's no \usepackage, and to cursor position if
--- there's neither; pass at_cursor=true to always insert at the cursor
--- instead.
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

  insert_package_usepackage(at_cursor)
end

return M
