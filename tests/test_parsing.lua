-- LaTeX text parsing, filename sanitizing, stylesheet reading, and the
-- buffer-level insertion helpers. No external tools needed.

local M = T.plugin()
local I = M._internal

-- strip_comment
T.check("strip: plain comment", I.strip_comment("abc % def") == "abc ")
T.check("strip: escaped percent kept", I.strip_comment("50\\% of x % c") == "50\\% of x ")
T.check("strip: double backslash then % is a comment", I.strip_comment("a\\\\% c") == "a\\\\")
T.check("strip: no comment", I.strip_comment("plain") == "plain")

-- line_defines_incfig
T.check("defines: \\newcommand", I.line_defines_incfig("\\newcommand{\\incfig}[2]{%") == true)
T.check("defines: \\def\\incfig", I.line_defines_incfig("\\def\\incfig#1#2{...}") == true)
T.check("defines: NewDocumentCommand", I.line_defines_incfig("\\NewDocumentCommand{\\incfig}{mm}{}") == true)
T.check("defines: commented out ignored", I.line_defines_incfig("% \\newcommand{\\incfig}[2]{...}") == false)
T.check("defines: \\incfigwide is not \\incfig", I.line_defines_incfig("\\newcommand{\\incfigwide}[2]{...}") == false)
T.check("defines: a usage is not a definition", I.line_defines_incfig("\\incfig{a}{b}") == false)

-- extract_arg_names
local names = I.extract_arg_names("\\usepackage[opt]{a, b}", "usepackage")
T.check("args: options skipped, names split", #names == 2 and names[1] == "a" and names[2] == "b", names)
T.check("args: commented usepackage ignored", #I.extract_arg_names("% \\usepackage{lextern-ipe}", "usepackage") == 0)
T.check("args: usepackage before a comment kept", I.extract_arg_names("\\usepackage{a,b} % x", "usepackage")[2] == "b")
T.check("args: other command ignored", #I.extract_arg_names("\\RequirePackage{x}", "usepackage") == 0)

-- sanitize_filename
T.check("sanitize: title -> slug", I.sanitize_filename("My Cool Figure!") == "my-cool-figure")
T.check("sanitize: dashes collapsed and trimmed", I.sanitize_filename("-a -- b-") == "a-b")
local _, err = I.sanitize_filename("日本語")
T.check("sanitize: non-ASCII-only name errors clearly", err ~= nil and err:find("ASCII", 1, true) ~= nil, err)

-- read_stylesheet
T.write(T.here .. "/s.isy", '<?xml version="1.0"?>\n<!DOCTYPE ipestyle SYSTEM "ipe.dtd">\n<ipestyle name="x">\n</ipestyle>\n')
local xml = I.read_stylesheet(T.here .. "/s.isy")
T.check("stylesheet: xml declaration and doctype stripped", xml == '<ipestyle name="x">\n</ipestyle>\n', xml)
T.write(T.here .. "/bad.isy", "not a stylesheet")
local _, sheet_err = I.read_stylesheet(T.here .. "/bad.isy")
T.check("stylesheet: non-stylesheet rejected", sheet_err ~= nil and sheet_err:find("<ipestyle", 1, true) ~= nil, sheet_err)
local _, missing_err = I.read_stylesheet(T.here .. "/nope.isy")
T.check("stylesheet: missing file rejected", missing_err ~= nil and missing_err:find("Cannot read", 1, true) ~= nil, missing_err)

-- \usepackage anchoring across a multi-line option bracket
T.edit_tex("anchor.tex", {
  "\\documentclass{article}",
  "\\usepackage[",
  "  colorlinks,",
  "  linkcolor=blue, % 50% nicer",
  "]{hyperref}",
  "% \\usepackage{commented}",
  "\\begin{document}",
  "\\end{document}",
})
M.define_incfig(false)
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
T.check("anchor: after the multi-line \\usepackage closes", lines[6] == "\\usepackage{lextern-ipe}", lines)
T.check("anchor: commented \\usepackage not used", lines[7] == "% \\usepackage{commented}")

-- commented-out preamble doesn't count
T.edit_tex("commented.tex", {
  "\\documentclass{article}",
  "% \\usepackage{lextern-ipe}",
  "% \\newcommand{\\incfig}[2]{x}",
  "\\begin{document}",
  "\\end{document}",
})
T.check("commented preamble: \\incfig not defined", I.incfig_is_defined() == false)
T.check("commented package: library not loaded", I.library_package_is_loaded() == false)

-- cache keyed on changedtick
local calls = 0
local real_defined = I.incfig_is_defined
T.edit_tex("cache.tex", { "\\documentclass{article}", "\\usepackage{lextern-ipe}", "\\begin{document}", "\\end{document}" })
T.check("cache: found via buffer text", real_defined() == true)
vim.api.nvim_buf_set_lines(0, 1, 2, false, { "% \\usepackage{lextern-ipe}" })
T.check("cache: invalidated by an edit", real_defined() == false)
T.check("cache: (calls counter unused here)", calls == 0)

-- library_dir resolution
M.config.library_dir = "~/lextern-test-lib/"
T.check("library_dir: ~ expanded, trailing slash stripped", M.library_dir() == vim.env.HOME .. "/lextern-test-lib", M.library_dir())

-- insert_at_cursor
T.edit_tex("insert.tex", { "one", "", "three" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local lnum = I.insert_at_cursor("X")
T.check("insert: blank line replaced", lnum == 2 and vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == "X")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
lnum = I.insert_at_cursor("Y")
T.check("insert: non-blank line -> inserted below", lnum == 2 and vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == "Y")

T.done()
