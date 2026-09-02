local M = {}

-- Name of the LaTeX package this plugin generates and manages. Providing
-- \incfig (as a fallback -- \providecommand, safe even if \incfig is
-- already defined elsewhere), \incfiglib (library figures, labelled
-- fig:lib:<name>) and \incfiglibrary (the library path). Must be
-- discoverable by LaTeX via \usepackage, which requires package_dir()
-- (below) to be on TEXINPUTS -- see :checkhealth lextern_ipe.
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

  -- Path to the shared figure library (~ and $VARS expanded; avoid
  -- spaces, #, % -- it's used inside \includegraphics), separate from
  -- each document's own <basename>_figures dir. Created on first use,
  -- per dir_create_mode. Used by :AddFigure/:EditFigure/:InsertFigure
  -- with --lib. Baked into the generated lextern-ipe.sty package as
  -- \incfiglibrary (see PACKAGE_NAME above) -- changing this only takes
  -- effect after the next setup()/Neovim restart regenerates the
  -- package; already-\usepackage{lextern-ipe}'d documents pick it up
  -- automatically at their next compile, no per-document edits needed.
  library_dir = vim.fn.stdpath("data") .. "/lextern_ipe/library",

  -- Whether :AddFigure --lib/:InsertFigure --lib prompt before
  -- auto-inserting \usepackage{lextern-ipe} (which provides \incfiglib)
  -- when it can't find the package loaded in the buffer or its
  -- packages: "ask" (default), "always", "never"
  confirm_missing_library_package = "ask",

  -- Open Ipe as a floating, centered window. Hyprland only: it's done
  -- by evaluating hl.exec_cmd(...) inside the compositor via
  -- `hyprctl eval` (see lua/lextern_ipe/hyprland.lua). Falls back to a
  -- normal launch, with a warning, when not running under Hyprland.
  -- Ignored when launch_cmd is set.
  floating = false,

  -- Floating window size in pixels, { width, height }
  float_size = { 800, 900 },

  -- Optional function(filepath) to launch IPE yourself, for any other
  -- compositor/WM. Receives the absolute path to the .ipe file and
  -- takes precedence over `floating`. When nil, IPE is launched as a
  -- plain detached job (or floating, per above).
  launch_cmd = nil,

  -- Ipe stylesheets (.isy files, paths; ~ is expanded) embedded into
  -- every *new* figure, after the "basic" sheet from
  -- templates/template.ipe. This is how figures get the same
  -- fonts/macros as your document: a sheet whose <preamble> holds your
  -- \usepackage lines -- see templates/preamble.isy for a starter and
  -- the README's "Figure stylesheets" section. Ipe only ever renders a
  -- figure with the sheets embedded in its file (the IPESTYLES
  -- environment variable is a *directory search list* for Ipe's own
  -- dialogs, not a way to apply a sheet), so existing figures are
  -- updated from inside Ipe: Edit > Style sheets, or Update style
  -- sheets (Ctrl+Shift+U).
  stylesheets = {},
}

--- Pristine copy of the defaults, taken before setup() merges user
--- options into M.config. :checkhealth uses it to flag option names
--- it doesn't recognize (a typo or a removed option is otherwise
--- silently ignored). launch_cmd defaults to nil so it doesn't appear
--- here; the health check special-cases it.
M.defaults = vim.deepcopy(M.config)

-- ============================================================
-- Watcher state
-- ============================================================

--- directory (with trailing slash) -> {
---   handle  = <uv fs_event>,
---   timers  = { [filename] = <uv timer> }  -- armed debounce timers
---   busy    = { [filename] = true }        -- export in flight
---   pending = { [filename] = true }        -- save landed while busy
---   exports = <completed export count>
--- }
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

--- config.library_dir as an absolute path without a trailing slash:
--- ~ and $VARS expanded (vim.fn.isdirectory/mkdir don't expand ~, so
--- a literal "~" directory would get created and baked into the .sty
--- as an active character). Exposed as M.library_dir() for the health
--- check.
local function resolved_library_dir()
  local dir = vim.fn.expand(M.config.library_dir or "")
  return (dir:gsub("/+$", ""))
end
M.library_dir = resolved_library_dir

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

  content = content .. string.format("\\newcommand{\\incfiglibrary}{%s}\n", resolved_library_dir())

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
    return nil, string.format(
      "Figure name needs at least one ASCII letter or digit (other characters are dropped from the filename): %q",
      name
    )
  end
  return result
end

--- Commands that insert LaTeX into the buffer need a named (La)TeX
--- buffer. Checked *before* prompting for a figure name, so the
--- user doesn't type one only to be told there's no file.
--- Returns true or nil + error message.
local function check_tex_buffer()
  if vim.fn.expand("%:p") == "" then
    return nil, "No file open (save the buffer first so figures have somewhere to live)"
  end
  local ft = vim.bo.filetype
  if ft ~= "tex" and ft ~= "latex" and ft ~= "plaintex" then
    return nil, "Not a LaTeX buffer (filetype=" .. (ft == "" and "none" or ft) .. ")"
  end
  return true
end

--- Ensure a directory exists, creating it based on config
--- Returns true or nil + error message
local function ensure_dir(directory)
  if vim.fn.isdirectory(directory) == 1 then
    return true
  end

  local function do_mkdir()
    if vim.fn.mkdir(directory, "p") == 0 then
      return nil, "Failed to create directory: " .. directory
    end
    vim.notify("Created figures directory: " .. directory, vim.log.levels.INFO)
    return true
  end

  local mode = M.config.dir_create_mode

  if mode == "never" then
    return nil, "Directory does not exist: " .. directory
  elseif mode == "always" then
    return do_mkdir()
  elseif mode == "ask" then
    local response = vim.fn.confirm(
      "Figures directory does not exist:\n" .. directory .. "\n\nCreate it?",
      "&Yes\n&No", 1
    )
    if response ~= 1 then
      return nil, "Directory creation cancelled"
    end
    return do_mkdir()
  end

  return nil, "Invalid dir_create_mode: " .. tostring(mode)
end

--- Absolute path (with trailing slash) of the current buffer's figures
--- directory, foo.tex -> foo_figures/, without creating it. Returns
--- the path or nil + error message.
local function figures_dir_path()
  local current = vim.fn.expand("%:p")
  if current == "" then
    return nil, "No file open"
  end
  local dir = vim.fn.fnamemodify(current, ":h")
  local basename = vim.fn.fnamemodify(current, ":t:r")
  return dir .. "/" .. basename .. "_figures/"
end

--- Absolute path (with trailing slash) of the shared figure library,
--- without creating it.
local function library_dir_path()
  return resolved_library_dir() .. "/"
end

--- Get the absolute path to the figures directory, creating it if
--- needed per dir_create_mode. Returns the path (with trailing slash)
--- or nil + error message.
local function get_figures_dir()
  local fig_dir, err = figures_dir_path()
  if not fig_dir then
    return nil, err
  end
  local ok
  ok, err = ensure_dir(fig_dir)
  if not ok then
    return nil, err
  end
  return fig_dir
end

--- Get the absolute path to the shared figure library, creating it if
--- needed per dir_create_mode. Returns the path (with trailing slash)
--- or nil + error message.
local function get_library_dir()
  local dir = library_dir_path()
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

--- Strip a LaTeX comment: everything from the first % that isn't
--- escaped (preceded by an odd number of backslashes). Without this,
--- a commented-out "% \usepackage{lextern-ipe}" or
--- "% \newcommand{\incfig}..." satisfies the definition checks and
--- the user gets a LaTeX error instead of a prompt.
local function strip_comment(line)
  local from = 1
  while true do
    local p = line:find("%", from, true)
    if not p then
      return line
    end
    local backslashes = 0
    local j = p - 1
    while j >= 1 and line:sub(j, j) == "\\" do
      backslashes = backslashes + 1
      j = j - 1
    end
    if backslashes % 2 == 0 then
      return line:sub(1, p - 1)
    end
    from = p + 1
  end
end

--- Whether a line looks like a definition of \incfig (as opposed to a
--- usage, e.g. \incfig{foo}{caption}). Comments are ignored, and the
--- name must end at a non-letter so \incfigwide etc. don't match.
local function line_defines_incfig(line)
  line = strip_comment(line)
  if not line:find("\\incfig%f[^%a]") then
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
--- "\command[options]{name1,name2}" invocation on a line (ignoring
--- anything commented out)
local function extract_arg_names(line, command)
  line = strip_comment(line)
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

--- Filename without its .cls/.sty extension
local function stem_of(filename)
  return (filename:gsub("%.[^.]*$", ""))
end

--- Resolve a list of .cls/.sty filenames with a *single* kpsewhich
--- invocation (each process costs ~100ms; a tikz+hyperref preamble
--- at depth 2 is ~30 files, so one call per file froze Neovim for
--- seconds). Returns basename -> absolute path for the files found;
--- missing ones are simply absent. kpsewhich prints one line per
--- argument (empty when not found) and exits non-zero if any was
--- missing, so the exit code is ignored and results are matched back
--- by basename rather than by position.
local function kpsewhich_resolve(filenames)
  local resolved = {}
  if #filenames == 0 then
    return resolved
  end
  local cmd = { "kpsewhich" }
  vim.list_extend(cmd, filenames)
  local output = vim.fn.system(cmd)
  for line in output:gmatch("[^\r\n]+") do
    local path = vim.trim(line)
    if path ~= "" then
      resolved[vim.fn.fnamemodify(path, ":t")] = path
    end
  end
  return resolved
end

--- Breadth-first walk of \documentclass/\usepackage/\RequirePackage
--- names starting from `lines`, resolving each level via one batched
--- kpsewhich call, up to config.kpsewhich_depth levels of further
--- indirection (1 = only what `lines` names directly; each additional
--- level follows one more hop of \RequirePackage/\usepackage inside
--- whatever was just resolved). Calls predicate(stem, file_lines) for
--- every candidate encountered -- stem is the filename without its
--- .cls/.sty extension, checked *before* resolving the level's files
--- (so a predicate that only needs the name, like matching this
--- plugin's own package, doesn't cost a kpsewhich round-trip);
--- file_lines is the resolved file's content on the second call.
--- Stops and returns true as soon as predicate matches; false if
--- kpsewhich isn't on PATH, kpsewhich_depth <= 0, or nothing matched.
local function walk_kpsewhich_packages(lines, predicate)
  local depth = M.config.kpsewhich_depth or 1
  if depth <= 0 or not has_command("kpsewhich") then
    return false
  end

  local visited = {}
  local queue = package_filenames(lines)

  for level = 1, depth do
    -- Name-only pass first: free, and may short-circuit the walk
    local pending = {}
    for _, filename in ipairs(queue) do
      if not visited[filename] then
        visited[filename] = true
        if predicate(stem_of(filename), nil) then
          return true
        end
        table.insert(pending, filename)
      end
    end

    local resolved = kpsewhich_resolve(pending)
    local next_queue = {}
    for _, filename in ipairs(pending) do
      local path = resolved[vim.fn.fnamemodify(filename, ":t")]
      local file_lines = path and read_file_lines(path)
      if file_lines then
        if predicate(stem_of(filename), file_lines) then
          return true
        end
        if level < depth then
          vim.list_extend(next_queue, package_filenames(file_lines))
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

--- Buffer-local memo for the (kpsewhich-backed, hence slow) checks
--- below, keyed on b:changedtick: both positive *and* negative results
--- are reused until the buffer is edited. Negative caching matters --
--- when \incfig genuinely isn't defined yet, ensure_incfig_preamble
--- and define_incfig both check within one :AddFigure, and each
--- :AddFigure --lib adds a third check; without it every one of those
--- re-ran the full walk.
local function cached_check(key, compute)
  local tick = vim.b.changedtick
  local cache = vim.b[key]
  if cache and cache.tick == tick then
    return cache.result
  end
  local result = compute()
  vim.b[key] = { tick = tick, result = result }
  return result
end

--- Check whether \incfig is defined, in the buffer, in a loaded
--- class/package, or via this plugin's own lextern-ipe.sty (loaded
--- directly, or indirectly -- e.g. \RequirePackage{lextern-ipe} inside
--- a custom class file). Cached per buffer until the next edit.
local function incfig_is_defined()
  return cached_check("lextern_ipe_incfig_check", function()
    return has_incfig_defined() or has_lextern_ipe_package_loaded() or has_incfig_in_loaded_packages()
  end)
end

--- Check whether lextern-ipe.sty (and so \incfiglibrary) is loaded, in
--- the buffer directly or transitively (e.g. via a custom class file's
--- own \RequirePackage{lextern-ipe}). Cached per buffer until the next
--- edit.
local function library_package_is_loaded()
  return cached_check("lextern_ipe_library_check", function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return has_lextern_ipe_package_loaded()
      or walk_kpsewhich_packages(lines, function(stem)
        return stem == PACKAGE_NAME
      end)
  end)
end

--- Find the 1-based line number of a line containing `pattern`
--- (outside comments) in the current buffer, or nil if there isn't
--- one. want_last=true returns the last match (for \usepackage, where
--- anchoring after the latest one reads naturally); false/omitted
--- returns the first.
local function find_line(pattern, want_last)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found = nil
  for i, line in ipairs(lines) do
    if strip_comment(line):find(pattern, 1, true) then
      found = i
      if not want_last then
        return found
      end
    end
  end
  return found
end

--- Given the 1-based line where a \usepackage/\documentclass starts,
--- return the line where its arguments end -- the same line usually,
--- but a \usepackage[\n opt,\n]{pkg} spread over several lines would
--- otherwise get the new line inserted inside its option bracket.
--- Walks forward until brackets and braces balance; gives up (and
--- returns `start`) after 50 lines so a stray brace can't send the
--- insertion to the end of the document.
local function end_of_command(start)
  local lines = vim.api.nvim_buf_get_lines(0, start - 1, start - 1 + 50, false)
  local depth = 0
  for i, raw in ipairs(lines) do
    for ch in strip_comment(raw):gmatch("[%[%]{}]") do
      if ch == "[" or ch == "{" then
        depth = depth + 1
      else
        depth = depth - 1
      end
    end
    if depth <= 0 then
      return start + i - 1
    end
  end
  return start
end

--- Insert text as new lines at the cursor: replacing the current line
--- if it's blank (so :AddFigure on an empty line puts the figure
--- there instead of leaving the blank above it), otherwise below it.
--- Leaves the cursor on the last inserted line and returns its
--- 1-based number.
local function insert_at_cursor(text)
  local lines = vim.split(text, "\n", { plain = true })
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local last
  if vim.api.nvim_get_current_line():match("^%s*$") then
    vim.api.nvim_buf_set_lines(0, row - 1, row, false, lines)
    last = row + #lines - 1
  else
    vim.api.nvim_buf_set_lines(0, row, row, false, lines)
    last = row + #lines
  end
  vim.api.nvim_win_set_cursor(0, { last, 0 })
  return last
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

  -- Make sure the package we're about to reference actually exists --
  -- it's normally generated by setup(), but the commands work without
  -- setup() ever having been called.
  if vim.fn.filereadable(package_dir() .. "/" .. PACKAGE_NAME .. ".sty") == 0 then
    local ok, err = write_package_file()
    if not ok then
      vim.notify("lextern_ipe: failed to write " .. PACKAGE_NAME .. ".sty: " .. err, vim.log.levels.ERROR)
    end
  end

  if at_cursor then
    insert_at_cursor(line)
    return
  end

  local anchor = find_line("\\usepackage", true) or find_line("\\documentclass")
  if not anchor then
    vim.notify(
      "No \\usepackage or \\documentclass line found; inserting at cursor instead.",
      vim.log.levels.INFO
    )
    insert_at_cursor(line)
    return
  end

  anchor = end_of_command(anchor)
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
--- appear to be loaded yet -- needed for \incfiglib specifically.
--- Deliberately narrower than incfig_is_defined(): \incfig might
--- already be available some other way (buffer text, an external
--- class/package), but \incfiglib is only ever provided by this
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
    "\\incfiglib isn't available (\\usepackage{lextern-ipe} not found in this buffer or loaded packages).\n\nInsert it now?",
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

  local function plain_launch()
    vim.fn.jobstart({ "ipe", filepath }, { detach = true })
  end

  if M.config.launch_cmd then
    M.config.launch_cmd(filepath)
  elseif M.config.floating then
    local hyprland = require("lextern_ipe.hyprland")
    if not hyprland.is_available() then
      vim.notify(
        "lextern_ipe: floating=true needs Hyprland (hyprctl + HYPRLAND_INSTANCE_SIGNATURE); opening Ipe normally."
          .. " Use launch_cmd for other compositors.",
        vim.log.levels.WARN
      )
      plain_launch()
    else
      hyprland.launch({ "ipe", filepath }, M.config.float_size, function(err)
        vim.notify("lextern_ipe: floating launch failed (" .. err .. "); opening Ipe normally", vim.log.levels.WARN)
        plain_launch()
      end)
    end
  else
    plain_launch()
  end

  return true
end

--- Export an .ipe file to PDF using ipetoipe, asynchronously -- it
--- runs pdflatex for any figure containing text, which froze the
--- editor for a second or more per save when this was synchronous.
--- Calls callback(true) or callback(nil, err) on the main loop.
local function export_to_pdf(ipe_path, callback)
  if not has_command("ipetoipe") then
    callback(nil, "ipetoipe is not installed")
    return
  end
  vim.system({ "ipetoipe", "-pdf", ipe_path }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true)
        return
      end
      local detail = vim.trim((result.stderr ~= "" and result.stderr) or result.stdout or "")
      callback(nil, string.format("ipetoipe failed (exit %d): %s", result.code, detail))
    end)
  end)
end

--- Read a .isy stylesheet for embedding into a figure: the
--- <ipestyle>...</ipestyle> element with any leading XML declaration
--- and DOCTYPE stripped (Ipe's own shipped sheets have them; they're
--- only valid at the top of a standalone file, not nested inside an
--- <ipe> document). Returns the XML text or nil + error message.
local function read_stylesheet(path)
  local f = io.open(path, "r")
  if not f then
    return nil, "Cannot read stylesheet: " .. path
  end
  local content = f:read("*all")
  f:close()
  content = content:gsub("^%s*<%?xml.-%?>%s*", "")
  content = content:gsub("^%s*<!DOCTYPE.->%s*", "")
  if not content:find("<ipestyle", 1, true) then
    return nil, "Not an Ipe stylesheet (no <ipestyle> element): " .. path
  end
  -- (not gsub("%s*$", "\n"): Lua's gsub also matches the empty string
  -- at the very end after a non-empty match, doubling the newline)
  return (content:gsub("%s+$", "")) .. "\n"
end

--- Copy the plugin template to create a new .ipe file, embedding
--- config.stylesheets before the first <page> (Ipe cascades sheets
--- in order, so they layer on top of the template's "basic" sheet).
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

  -- Embed configured stylesheets. A missing/invalid sheet is an error
  -- rather than silently skipped: the user asked for it, and a figure
  -- created without it would render with the wrong fonts/macros.
  local sheets = M.config.stylesheets or {}
  if #sheets > 0 then
    local page_at = content:find("<page>", 1, true)
    if not page_at then
      return nil, "Template has no <page> element: " .. template
    end
    local extra = {}
    for _, sheet in ipairs(sheets) do
      local xml, sheet_err = read_stylesheet(vim.fn.expand(sheet))
      if not xml then
        return nil, sheet_err
      end
      table.insert(extra, xml)
    end
    content = content:sub(1, page_at - 1) .. table.concat(extra) .. content:sub(page_at)
  end

  -- Write to destination
  f = io.open(dest_path, "w")
  if not f then
    return nil, "Cannot write file: " .. dest_path
  end
  f:write(content)
  f:close()

  return true
end

-- ============================================================
-- File watcher
-- ============================================================

--- Run (or queue) the export of one file in a watched directory,
--- serialized per file: if a save lands while its export is still in
--- flight, one more export runs after it finishes rather than two
--- ipetoipe processes racing to write the same PDF.
local function run_export(directory, filename)
  local watcher = M._watchers[directory]
  if not watcher then
    return
  end
  if watcher.busy[filename] then
    watcher.pending[filename] = true
    return
  end

  local ipe_path = directory .. filename
  if vim.fn.filereadable(ipe_path) == 0 then
    return -- deleted or renamed away between the event and now
  end

  watcher.busy[filename] = true
  export_to_pdf(ipe_path, function(ok, err)
    watcher.busy[filename] = nil
    if ok then
      watcher.exports = watcher.exports + 1
      local pdf_name = filename:gsub("%.ipe$", ".pdf")
      vim.api.nvim_echo({ { pdf_name .. " ✓", "MoreMsg" } }, false, {})
    else
      vim.notify("Export failed: " .. filename .. "\n" .. (err or ""), vim.log.levels.ERROR)
    end
    if watcher.pending[filename] then
      watcher.pending[filename] = nil
      run_export(directory, filename)
    end
  end)
end

--- Build the fs-event callback for one watched directory. Saves are
--- debounced on the trailing edge: every event (re)arms a per-file
--- timer and the export runs debounce_ms after the *last* one, so a
--- save Ipe writes in several steps is exported once, complete,
--- instead of on the first partial write.
local function on_fs_change(directory)
  return function(err, filename)
    if err or not filename or not filename:match("%.ipe$") then
      return
    end

    local watcher = M._watchers[directory]
    if not watcher then
      return
    end

    local timer = watcher.timers[filename]
    if not timer then
      timer = vim.uv.new_timer()
      watcher.timers[filename] = timer
    end
    timer:stop()
    timer:start(M.config.debounce_ms, 0, function()
      vim.schedule(function()
        local current = M._watchers[directory]
        if current and current.timers[filename] == timer then
          current.timers[filename] = nil
          timer:close()
        end
        run_export(directory, filename)
      end)
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

  -- Normalize to a trailing slash: watchers are keyed by it, and file
  -- paths are built as directory .. filename.
  if directory:sub(-1) ~= "/" then
    directory = directory .. "/"
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

  M._watchers[directory] = { handle = handle, timers = {}, busy = {}, pending = {}, exports = 0 }

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
    for _, timer in pairs(watcher.timers) do
      timer:stop()
      timer:close()
    end
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
    table.insert(lines, string.format("%s (%d exports)", dir, watcher.exports))
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

  -- clear = true so calling setup() again (e.g. to regenerate the
  -- package after changing library_dir) doesn't stack autocmds
  local group = vim.api.nvim_create_augroup("lextern_ipe", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
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

--- Build the figure-inclusion line for `name` in target_dir:
--- \incfiglib{name}{} for the library (the package resolves the path
--- and labels it fig:lib:name), \incfig{reldir/name}{} for a per-file
--- figure. Also ensures the relevant preamble/package is present --
--- just the package check for the library (\incfiglib only comes from
--- the package, which provides \incfig too, so a separate \incfig
--- prompt would only ever offer to insert the same line twice).
local function incfig_line(use_library, name)
  if use_library then
    ensure_library_package()
    return string.format("\\incfiglib{%s}{}", name)
  end
  ensure_incfig_preamble()
  return string.format("\\incfig{%s/%s}{}", get_figures_reldir(), name)
end

--- Insert the inclusion line at cursor for `name` in
--- target_dir(use_library), leaving the cursor on the caption's
--- closing brace so `i` types straight into it.
local function insert_incfig_line(use_library, name)
  local line = incfig_line(use_library, name)
  local lnum = insert_at_cursor(line)
  vim.api.nvim_win_set_cursor(0, { lnum, #line - 1 })
end

--- Resolve the target directory *without creating it* and list its
--- figures, notifying on either failure. Returns (dir, figures), or
--- nil (already notified) if there's nothing to list -- offering to
--- create a directory just to report it's empty helps nobody.
local function list_target_figures(use_library)
  local dir, err
  if use_library then
    dir = library_dir_path()
  else
    dir, err = figures_dir_path()
  end
  if not dir then
    vim.notify(err, vim.log.levels.ERROR)
    return nil
  end

  local figures = vim.fn.isdirectory(dir) == 1 and list_figures(dir) or {}
  if #figures == 0 then
    vim.notify("No figures found in: " .. dir, vim.log.levels.INFO)
    return nil
  end

  return dir, figures
end

function M.create_figure(use_library)
  local ok_buf, buf_err = check_tex_buffer()
  if not ok_buf then
    vim.notify(buf_err, vim.log.levels.ERROR)
    return
  end

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

    insert_incfig_line(use_library, filename)

    open_ipe(ipe_path)
    ensure_watcher(dir)
    -- Export the (empty) figure right away so the document compiles
    -- immediately -- the \incfig line is already in the buffer, and
    -- the watcher only sees saves from here on.
    run_export(dir, filename .. ".ipe")

    vim.notify("Created: " .. filename .. ".ipe", vim.log.levels.INFO)
  end)
end

function M.edit_figure(use_library)
  local dir, figures = list_target_figures(use_library)
  if not dir then
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
  local ok_buf, buf_err = check_tex_buffer()
  if not ok_buf then
    vim.notify(buf_err, vim.log.levels.ERROR)
    return
  end

  local dir, figures = list_target_figures(use_library)
  if not dir then
    return
  end

  ui_select(figures, use_library and "Insert library figure" or "Insert figure", function(selected)
    if not selected then
      return
    end

    insert_incfig_line(use_library, selected)
  end)
end

--- Ensure \usepackage{lextern-ipe} is present (providing \incfig as a
--- fallback and \incfiglibrary). By default it's placed right after
--- the last \usepackage line, falling back to right after
--- \documentclass if there's no \usepackage, and to cursor position if
--- there's neither; pass at_cursor=true to always insert at the cursor
--- instead.
function M.define_incfig(at_cursor)
  local ok_buf, buf_err = check_tex_buffer()
  if not ok_buf then
    vim.notify(buf_err, vim.log.levels.ERROR)
    return
  end

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

-- ============================================================
-- Test hooks
-- ============================================================

--- Internals exposed for the test suite (tests/). Not a public API;
--- anything here may change without notice.
M._internal = {
  strip_comment = strip_comment,
  line_defines_incfig = line_defines_incfig,
  extract_arg_names = extract_arg_names,
  end_of_command = end_of_command,
  incfig_is_defined = incfig_is_defined,
  library_package_is_loaded = library_package_is_loaded,
  sanitize_filename = sanitize_filename,
  read_stylesheet = read_stylesheet,
  insert_at_cursor = insert_at_cursor,
  walk_kpsewhich_packages = walk_kpsewhich_packages,
}

return M
