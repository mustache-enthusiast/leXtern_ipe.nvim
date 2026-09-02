-- Resolving \incfig / lextern-ipe through loaded classes and packages
-- via kpsewhich: batching (one process per level) and caching.

T.requires("kpsewhich")

-- A scratch texmf tree kpsewhich can see
local texmf = T.here .. "/texmf"
T.write(texmf .. "/mycls.cls", "\\ProvidesClass{mycls}\n\\LoadClass{article}\n\\RequirePackage{amsmath}\n\\RequirePackage{lextern-ipe}\n")
T.write(texmf .. "/defpkg.sty", "\\ProvidesPackage{defpkg}\n\\newcommand{\\incfig}[2]{#1 #2}\n")
vim.env.TEXINPUTS = texmf .. ":" .. (vim.env.TEXINPUTS or "")
if vim.trim(vim.fn.system({ "kpsewhich", "article.cls" })) == "" then
  T.skip("kpsewhich can't find article.cls (no LaTeX installed?)")
end

local M = T.plugin({ kpsewhich_depth = 2 })
local I = M._internal

local calls = 0
local real_system = vim.fn.system
vim.fn.system = function(cmd, ...)
  if type(cmd) == "table" and cmd[1] == "kpsewhich" then
    calls = calls + 1
  end
  return real_system(cmd, ...)
end
local function probe(fn)
  calls = 0
  local result = fn()
  return result, calls
end

T.edit_tex("plain.tex", {
  "\\documentclass{article}",
  "\\usepackage{amsmath,amssymb}",
  "\\usepackage{graphicx}",
  "\\begin{document}",
  "\\end{document}",
})
local found, n = probe(I.incfig_is_defined)
T.check("plain preamble: not defined", found == false)
T.check("plain preamble: at most one kpsewhich call per level", n >= 1 and n <= 2, n)
found, n = probe(I.incfig_is_defined)
T.check("repeat, same buffer: cached, no calls", found == false and n == 0, n)
vim.api.nvim_buf_set_lines(0, -1, -1, false, { "% edit" })
found, n = probe(I.incfig_is_defined)
T.check("after an edit: re-resolved", found == false and n >= 1, n)

T.edit_tex("custom.tex", { "\\documentclass{mycls}", "\\begin{document}", "\\end{document}" })
found, n = probe(I.incfig_is_defined)
T.check("custom class requiring lextern-ipe: found at depth 2", found == true, n)
T.check("... using one call (class resolved, package matched by name)", n == 1, n)
found, n = probe(I.library_package_is_loaded)
T.check("library package found through the class", found == true)

M.config.kpsewhich_depth = 1
vim.api.nvim_buf_set_lines(0, -1, -1, false, { "% bump" })
found = probe(I.incfig_is_defined)
T.check("depth 1: the class's \\RequirePackage is not followed", found == false)

M.config.kpsewhich_depth = 2
T.edit_tex("defpkg.tex", { "\\documentclass{article}", "\\usepackage{defpkg}", "\\begin{document}", "\\end{document}" })
found = probe(I.incfig_is_defined)
T.check("\\newcommand{\\incfig} inside a .sty: found", found == true)

M.config.kpsewhich_depth = 0
vim.api.nvim_buf_set_lines(0, -1, -1, false, { "% bump" })
found, n = probe(I.incfig_is_defined)
T.check("depth 0: no kpsewhich at all", found == false and n == 0, n)

T.done()
