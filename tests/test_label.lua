-- :LabelFigure: expanding \incfig into a labelled figure environment,
-- relabelling one that's already expanded, following references, and
-- the cases it refuses. No external tools needed -- the figures only
-- have to exist for the picker to list them.

T.stub_ui()
local M = T.plugin()

for _, name in ipairs({ "alpha", "beta" }) do
  T.write(T.here .. "/doc_figures/" .. name .. ".ipe", "x")
end
T.write(T.here .. "/lib/gamma.ipe", "x")

--- Reset doc.tex to `lines`, cursor on line `row`, and run
--- :LabelFigure over the figure at `pick` with `input` as the label.
local function label(lines, row, input, opts)
  opts = opts or {}
  T.edit_tex("doc.tex", lines)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  T.answers.select = opts.pick or 1
  T.answers.input = input
  T.reset()
  M.label_figure(opts.lib)
end

local preamble = { "\\documentclass{article}", "\\usepackage{lextern-ipe}", "\\begin{document}" }

--- A document body appended to the standard preamble
local function doc(...)
  local lines = vim.deepcopy(preamble)
  vim.list_extend(lines, { ... })
  table.insert(lines, "\\end{document}")
  return lines
end

-- an \incfig call becomes the figure environment it stands for
label(doc("\\incfig{doc_figures/alpha}{A caption}", "As in \\ref{fig:alpha}."), 4, "banach")
T.check("call expanded to a figure environment", T.buffer():find([[
\begin{figure}[htbp]
    \centering
    \includegraphics[width=0.8\linewidth]{doc_figures/alpha.pdf}
    \caption{A caption}
    \label{fig:banach}
\end{figure}]], 1, true) ~= nil, T.buffer())
T.check("the \\ref followed the rename", T.buffer():find("As in \\ref{fig:banach}.", 1, true) ~= nil, T.buffer())
T.check("reported the label and the reference", T.noted("Labelled alpha as fig:banach (1 reference updated)"), T.notes)
T.check("cursor left on the \\label", vim.api.nvim_get_current_line():find("\\label{fig:banach}", 1, true) ~= nil)

-- a bare name gets the fig: prefix, a prefixed one is taken as written
label(doc("\\incfig{doc_figures/alpha}{}"), 4, "eq:cauchy")
T.check("a label with a prefix of its own is kept", T.buffer():find("\\label{eq:cauchy}", 1, true) ~= nil, T.buffer())

-- relabelling an expanded figure rewrites the \label in place
label(doc(
  "\\begin{figure}[htbp]",
  "    \\centering",
  "    \\includegraphics[width=0.8\\linewidth]{doc_figures/alpha.pdf}",
  "    \\caption{Kept}",
  "    \\label{fig:banach}",
  "\\end{figure}",
  "See \\cref{fig:banach,fig:lib:gamma} and \\autoref{fig:banach}."
), 4, "hahn")
T.check("relabelled in place, no second environment", select(2, T.buffer():gsub("\\begin{figure}", "")) == 1, T.buffer())
T.check("the new label replaced the old", T.buffer():find("\\label{fig:hahn}", 1, true) ~= nil, T.buffer())
T.check("the caption survived", T.buffer():find("\\caption{Kept}", 1, true) ~= nil)
T.check("\\cref list rewritten entry by entry", T.buffer():find("\\cref{fig:hahn,fig:lib:gamma}", 1, true) ~= nil, T.buffer())
T.check("\\autoref rewritten too", T.buffer():find("\\autoref{fig:hahn}", 1, true) ~= nil)
T.check("both references counted", T.noted("(2 references updated)"), T.notes)

-- an expanded figure with no \label of its own gets one after the caption
label(doc(
  "\\begin{figure}[htbp]",
  "    \\includegraphics{doc_figures/alpha.pdf}",
  "    \\caption{No label yet}",
  "\\end{figure}"
), 5, "riesz")
T.check("\\label inserted after the caption", T.buffer():find("\\caption{No label yet}\n    \\label{fig:riesz}", 1, true) ~= nil, T.buffer())
T.check("nothing to rewrite, so no reference count", T.noted("Labelled alpha as fig:riesz") and not T.noted("reference"), T.notes)

-- indentation and comments are carried over
label(doc("    \\incfig{doc_figures/alpha}{} % draft"), 4, "sobolev")
T.check("indentation preserved", T.buffer():find("    \\begin{figure}[htbp]\n        \\centering", 1, true) ~= nil, T.buffer())
T.check("comment kept above the environment", T.buffer():find("    % draft\n    \\begin{figure}", 1, true) ~= nil, T.buffer())

-- braces in a caption, and a call split over several lines
label(doc("\\incfig{doc_figures/alpha}{A \\textbf{bold} caption}"), 4, "brace")
T.check("caption with nested braces kept whole",
  T.buffer():find("\\caption{A \\textbf{bold} caption}", 1, true) ~= nil, T.buffer())

label(doc("\\incfig%", "  {doc_figures/alpha}%", "  {Split over lines}"), 4, "split")
T.check("multi-line call parsed and replaced as a whole",
  T.buffer():find("\\caption{Split over lines}", 1, true) ~= nil
    and T.buffer():find("\\incfig", 1, true) == nil, T.buffer())

-- a commented-out figure is not a figure
label(doc("% \\incfig{doc_figures/alpha}{}"), 4, "banach")
T.check("commented-out \\incfig ignored", T.noted("isn't included in this buffer yet"), T.notes)
T.check("comment left as it was", T.buffer():find("% \\incfig{doc_figures/alpha}{}", 1, true) ~= nil)

-- a figure that isn't in the buffer, or a call sharing its line
label(doc("Nothing here."), 4, "banach")
T.check("figure not included: error names the fix", T.noted("alpha isn't included in this buffer yet (:InsertFigure adds it)"), T.notes)
T.check("figure not included: buffer untouched", T.buffer():find("Nothing here.", 1, true) ~= nil and T.buffer():find("figure", 1, true) == nil)

label(doc("Text before \\incfig{doc_figures/alpha}{} and after."), 4, "banach")
T.check("call sharing a line: refused with a reason", T.noted("shares its line with other text"), T.notes)
T.check("call sharing a line: buffer untouched", T.buffer():find("Text before \\incfig{doc_figures/alpha}{} and after.", 1, true) ~= nil)

-- a label LaTeX can't take is refused before anything is written
label(doc("\\incfig{doc_figures/alpha}{}"), 4, "a\\b")
T.check("backslash in a label: refused", T.noted("A label can't contain"), T.notes)
T.check("backslash in a label: nothing written", T.buffer():find("\\begin{figure}", 1, true) == nil)

-- a duplicate label is a warning, not a refusal
label(doc("\\incfig{doc_figures/alpha}{}", "\\section{S}\\label{fig:taken}"), 4, "taken")
T.check("duplicate label warned about", T.noted("multiply defined"), T.notes)
T.check("duplicate label still applied", T.buffer():find("\\label{fig:taken}\n\\end{figure}", 1, true) ~= nil, T.buffer())

-- the same figure twice: the one nearest the cursor wins
local twice = doc("\\incfig{doc_figures/alpha}{first}", "", "", "", "\\incfig{doc_figures/alpha}{second}")
label(twice, 8, "second-one")
T.check("nearest-to-cursor site labelled", T.buffer():find("\\caption{second}\n    \\label{fig:second-one}", 1, true) ~= nil, T.buffer())
T.check("the other call left alone", T.buffer():find("\\incfig{doc_figures/alpha}{first}", 1, true) ~= nil)
T.check("warned that there were two", T.noted("alpha appears 2 times"), T.notes)

-- --lib expands through \incfiglibrary rather than the library path
label(doc("\\incfiglib{gamma}{Lib}"), 4, "gamma-lemma", { lib = true })
T.check("library expansion goes through \\incfiglibrary",
  T.buffer():find("\\includegraphics[width=0.8\\linewidth]{\\incfiglibrary/gamma.pdf}", 1, true) ~= nil, T.buffer())
T.check("library figure labelled", T.buffer():find("\\label{fig:gamma-lemma}", 1, true) ~= nil)
T.check("library dir absent from the buffer", T.buffer():find(T.here .. "/lib", 1, true) == nil)

-- a per-file :LabelFigure doesn't reach into a library figure's environment
label(doc(
  "\\begin{figure}[htbp]",
  "    \\includegraphics{\\incfiglibrary/alpha.pdf}",
  "    \\label{fig:lib:alpha}",
  "\\end{figure}"
), 4, "banach")
T.check("library environment not matched without --lib", T.noted("isn't included in this buffer yet"), T.notes)

-- the picker itself is unchanged: no figures, no prompt
T.edit_tex("empty.tex", { "\\documentclass{article}" })
T.reset()
M.label_figure(false)
T.check("no figures dir: reported, nothing prompted", T.noted("No figures found"), T.notes)

M.stop_watcher()
T.done()
