-- Prompts, validation, directory handling, and cursor placement.

T.stub_ui()
local M = T.plugin({ dir_create_mode = "ask", confirm_missing_preamble = "never" })

-- validation happens before the name prompt
vim.cmd("enew!")
T.reset()
M.create_figure(false)
T.check("unnamed buffer: error, no name prompt", (T.prompts or 0) == 0 and T.noted("No file open"), T.notes)
T.write(T.here .. "/notes.md", "# notes\n")
vim.cmd("edit! notes.md")
vim.bo.filetype = "markdown"
T.reset()
M.create_figure(false)
T.check("non-tex buffer: error names the filetype", (T.prompts or 0) == 0 and T.noted("filetype=markdown"), T.notes)
M.define_incfig(false)
T.check(":DefineIncfig refuses a non-tex buffer", vim.fn.search("lextern-ipe", "nw") == 0)

-- listing never creates directories
T.edit_tex("doc.tex", { "\\documentclass{article}", "\\begin{document}", "x", "", "\\end{document}" })
T.reset()
M.insert_figure(false)
T.check(":InsertFigure with no figures dir: no create prompt, 'no figures'", #T.confirms == 0 and T.noted("No figures found"), { T.confirms, T.notes })
T.check("figures dir not created", vim.fn.isdirectory(T.here .. "/doc_figures") == 0)
M.edit_figure(true)
T.check(":EditFigure --lib with no library: no create prompt", #T.confirms == 0 and vim.fn.isdirectory(T.here .. "/lib") == 0)

-- dir_create_mode = "ask": declining is reported, accepting creates
T.answers.input = "Alpha"
T.answers.confirm = 2
T.reset()
M.create_figure(false)
T.check("dir prompt declined: cancelled, nothing created", T.noted("Directory creation cancelled") and vim.fn.isdirectory(T.here .. "/doc_figures") == 0, T.notes)
T.answers.confirm = 1
M.config.dir_create_mode = "always"

-- cursor placement
vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- the blank line
M.create_figure(false)
local line4 = vim.api.nvim_buf_get_lines(0, 3, 4, false)[1]
local cur = vim.api.nvim_win_get_cursor(0)
T.check("blank line replaced by \\incfig", line4 == "\\incfig{doc_figures/alpha}{}", line4)
T.check("cursor on the caption's closing brace", cur[1] == 4 and cur[2] == #line4 - 1 and line4:sub(cur[2] + 1, cur[2] + 1) == "}", cur)
vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- the "x" line
T.answers.input = "Beta"
M.create_figure(false)
T.check("non-blank line: inserted below it", vim.api.nvim_buf_get_lines(0, 3, 4, false)[1] == "\\incfig{doc_figures/beta}{}")

-- existing figure
T.reset()
M.create_figure(false)
T.check("existing figure: warned, not overwritten", T.noted("Figure already exists: beta.ipe"), T.notes)

-- --lib asks once, and declining doesn't re-ask
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "\\documentclass{article}", "\\begin{document}", "", "\\end{document}" })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
M.config.confirm_missing_preamble = "ask"
M.config.confirm_missing_library_package = "ask"
T.answers.confirm = 2
T.answers.input = "Gamma"
T.reset()
M.create_figure(true)
T.check("--lib with nothing defined: exactly one prompt, about \\incfiglib", #T.confirms == 1 and T.confirms[1]:find("\\incfiglib isn't available", 1, true) ~= nil, T.confirms)
T.check("--lib: figure line inserted regardless", vim.fn.search("\\\\incfiglib{gamma}{}", "nw") > 0)
T.check("--lib: declined, so no \\usepackage", vim.fn.search("usepackage{lextern-ipe}", "nw") == 0)
T.answers.confirm = 1

-- :DefineIncfig without a prior package file generates it
local sty = vim.fn.stdpath("data") .. "/lextern_ipe/lextern-ipe.sty"
os.remove(sty)
T.check("precondition: package removed", vim.fn.filereadable(sty) == 0)
M.define_incfig(false)
T.check(":DefineIncfig regenerated the package", vim.fn.filereadable(sty) == 1)
T.check("\\usepackage inserted after \\documentclass", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == "\\usepackage{lextern-ipe}", T.buffer())

-- setup() twice leaves one autocmd
M.setup({})
M.setup({})
T.check("setup() twice: one VimLeavePre autocmd", #vim.api.nvim_get_autocmds({ group = "lextern_ipe", event = "VimLeavePre" }) == 1)

-- floating without Hyprland falls back with a warning
M.config.launch_cmd = nil
M.config.floating = true
local sig = vim.env.HYPRLAND_INSTANCE_SIGNATURE
vim.env.HYPRLAND_INSTANCE_SIGNATURE = nil
local started
vim.fn.jobstart = function(cmd)
  started = cmd
  return 1
end
T.answers.input = "Delta"
T.reset()
M.create_figure(false)
T.check("floating without Hyprland: warned and launched plainly", T.noted("needs Hyprland") and started and started[1] == "ipe", { T.notes, started })
vim.env.HYPRLAND_INSTANCE_SIGNATURE = sig

M.stop_watcher()
T.done()
