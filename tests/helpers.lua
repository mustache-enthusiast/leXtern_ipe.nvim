-- Test helpers, loaded by tests/run.sh before each tests/test_*.lua.
--
-- Every test file runs in its own fresh headless Neovim (-u NONE) with
-- isolated XDG_* dirs and an empty working directory, so tests may
-- create files, directories, watchers and buffers freely. `T` is a
-- deliberate global: test files are scripts, not modules.

local root = vim.env.LEXTERN_TEST_ROOT
  or vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(root)
vim.cmd("runtime plugin/lextern_ipe.lua")

T = {
  root = root,
  here = vim.fn.getcwd(),
  count = 0,
  fails = 0,
  notes = {}, -- every vim.notify message since the last T.reset()
  confirms = {}, -- every vim.fn.confirm prompt since the last T.reset()
  answers = {}, -- stubbed UI answers, see T.stub_ui()
}

--- Record one check. `detail` is shown only on failure.
function T.check(label, cond, detail)
  T.count = T.count + 1
  if not cond then
    T.fails = T.fails + 1
  end
  local suffix = ""
  if not cond and detail ~= nil then
    suffix = "  -- " .. (type(detail) == "string" and detail or vim.inspect(detail))
  end
  print(string.format("%s %2d. %s%s", cond and "PASS" or "FAIL", T.count, label, suffix))
end

--- Whether any captured notification contains `text` (plain match)
function T.noted(text)
  for _, msg in ipairs(T.notes) do
    if msg:find(text, 1, true) then
      return true
    end
  end
  return false
end

function T.reset()
  T.notes = {}
  T.confirms = {}
end

-- Capture notifications instead of printing them
vim.notify = function(msg)
  table.insert(T.notes, msg)
end

--- Stub vim.ui.input / vim.ui.select / vim.fn.confirm so commands run
--- unattended. T.answers.input is what the name prompt returns;
--- T.answers.select picks the item at that index (default 1);
--- T.answers.confirm is the button number (default: the prompt's own
--- default).
function T.stub_ui()
  vim.ui.input = function(_, cb)
    T.prompts = (T.prompts or 0) + 1
    cb(T.answers.input)
  end
  vim.ui.select = function(items, _, cb)
    cb(items[T.answers.select or 1])
  end
  vim.fn.confirm = function(msg, _, default)
    table.insert(T.confirms, msg)
    return T.answers.confirm or default
  end
end

--- Plugin module with defaults suited to unattended runs
function T.plugin(opts)
  local M = require("lextern_ipe")
  M.setup(vim.tbl_extend("force", {
    dir_create_mode = "always",
    confirm_missing_preamble = "always",
    confirm_missing_library_package = "always",
    confirm_duplicate_preamble = "never",
    library_dir = T.here .. "/lib",
    kpsewhich_depth = 0,
    launch_cmd = function(path)
      T.launched = path
    end,
  }, opts or {}))
  return M
end

--- Contents of templates/template.ipe
function T.template()
  return table.concat(vim.fn.readfile(T.root .. "/templates/template.ipe"), "\n")
end

--- template.ipe with one LaTeX text label on the page
function T.figure_with_label(text)
  return (T.template():gsub("<page>", '<page>\n<text pos="100 100" type="label">' .. text .. "</text>", 1))
end

function T.write(path, body)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "w"))
  f:write(body)
  f:close()
end

function T.read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

function T.buffer()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

--- Open (creating if needed) a .tex file in the working dir
function T.edit_tex(name, lines)
  T.write(T.here .. "/" .. name, table.concat(lines, "\n") .. "\n")
  vim.cmd("edit! " .. name)
  vim.bo.filetype = "tex"
end

--- Wait for fn() to become true; returns only the boolean (vim.wait's
--- second return value would otherwise leak into T.check's detail)
function T.wait_for(fn, ms)
  local ok = vim.wait(ms or 15000, fn, 50)
  return ok
end

--- Run :checkhealth lextern_ipe and return the report text
function T.checkhealth()
  vim.cmd("silent checkhealth lextern_ipe")
  return T.buffer()
end

--- Skip the whole file (exit 0) -- e.g. a required executable is missing
function T.skip(reason)
  print("SKIP: " .. reason)
  vim.cmd("qa!")
end

function T.requires(...)
  for _, exe in ipairs({ ... }) do
    if vim.fn.executable(exe) == 0 then
      T.skip(exe .. " not on PATH")
    end
  end
end

--- Print the summary and exit; non-zero when anything failed
function T.done()
  print(string.format("RESULT %d/%d passed", T.count - T.fails, T.count))
  vim.cmd(T.fails > 0 and "cquit 1" or "qa!")
end

--- Run one test file, turning a Lua error into a failure exit
function T.run(path)
  local ok, err = pcall(dofile, path)
  if not ok then
    print("ERROR " .. tostring(err))
    vim.cmd("cquit 2")
  end
end
