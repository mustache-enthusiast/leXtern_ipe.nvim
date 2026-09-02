# leXtern_ipe.nvim

Neovim plugin for seamless [IPE](https://ipe.otfried.org/) figure integration with LaTeX documents.

Create, edit, and insert IPE figures from within Neovim with a couple of keystrokes. A built-in file watcher automatically exports figures to PDF on save, so your LaTeX document recompiles instantly.

## Dependencies

- **Neovim** >= 0.10
- **IPE** drawing editor (`ipe` and `ipetoipe` must be on PATH)

Figure name input and selection use Neovim's built-in `vim.ui.input`/`vim.ui.select`,
so they pick up whatever UI provider you have configured (e.g.
[dressing.nvim](https://github.com/stevearc/dressing.nvim),
[telescope-ui-select](https://github.com/nvim-telescope/telescope-ui-select.nvim)),
or fall back to Neovim's native prompts otherwise.

Run `:checkhealth lextern_ipe` to verify `ipe`/`ipetoipe` are on PATH, your
config is valid, whether `kpsewhich` is available (optional -- used to
resolve `\incfig` definitions in a loaded class/package; see
[LaTeX setup](#latex-setup)), and whether `TEXINPUTS` is set up correctly
(needed for the [figure library](#figure-library)).

## Setup

Lazy.nvim:
```lua
{
  "mustache-enthusiast/leXtern_ipe.nvim",
  ft = "tex",
  config = function()
    require("lextern_ipe").setup({
      -- How to handle a missing figures directory: "ask", "always", "never"
      dir_create_mode = "ask",

      -- Debounce interval for the file watcher (ms)
      debounce_ms = 100,

      -- How many levels of \RequirePackage/\usepackage indirection to
      -- follow when resolving whether \incfig (or \usepackage{lextern-ipe}
      -- specifically) is defined by a loaded class/package via
      -- kpsewhich. Default 2 so \RequirePackage{lextern-ipe} inside a
      -- custom \documentclass is found out of the box. 0 disables
      -- package resolution, falling back to a buffer-text-only check.
      kpsewhich_depth = 2,

      -- Whether :AddFigure/:InsertFigure prompt before auto-inserting a
      -- missing \incfig preamble: "ask", "always", "never"
      confirm_missing_preamble = "ask",

      -- Whether :DefineIncfig prompts before inserting a second \incfig
      -- definition when one is already found: "ask", "always", "never"
      confirm_duplicate_preamble = "ask",

      -- Absolute path to the shared figure library (see "Figure
      -- library" below), separate from each document's own
      -- <basename>_figures dir. Created on first use, per dir_create_mode.
      library_dir = vim.fn.stdpath("data") .. "/lextern_ipe/library",

      -- Whether :AddFigure --lib/:InsertFigure --lib prompt before
      -- auto-inserting \usepackage{lextern-ipe} (which provides
      -- \incfiglibrary) when it isn't loaded yet: "ask", "always", "never"
      confirm_missing_library_package = "ask",

      -- Optional function(filepath) to launch IPE yourself, e.g. to open
      -- it floating under a tiling WM. When nil, IPE is launched as a
      -- plain detached job. Example for Hyprland:
      --
      -- launch_cmd = function(filepath)
      --   local rules = "[float;size 900 700;center]"
      --   vim.fn.jobstart(
      --     { "hyprctl", "dispatch", "exec", rules, "--", "ipe", filepath },
      --     { detach = true }
      --   )
      -- end,
      launch_cmd = nil,

      -- Ipe stylesheets (.isy paths, ~ expanded) embedded into every new
      -- figure, e.g. one whose <preamble> holds your \usepackage lines
      -- so figure text matches your document (see "Figure stylesheets"
      -- below). Only affects figures created after the change.
      stylesheets = {},
    })
  end,
}
```

All config options are optional and the defaults are shown above.

## LaTeX setup

The `\incfig` command needs to be defined before you can use it. The plugin
generates and maintains a small LaTeX package, `lextern-ipe.sty`, at
`stdpath("data")/lextern_ipe/lextern-ipe.sty` (regenerated every time
`setup()` runs, so it always reflects your current `library_dir`). It
provides `\incfig` as a fallback (via `\providecommand`, so it's a no-op if
you already define `\incfig` yourself elsewhere -- e.g. in a shared class
file) and `\incfiglib` for library figures (see
[Figure library](#figure-library) below).

For LaTeX to find it via `\usepackage{lextern-ipe}`, add its directory to
`TEXINPUTS` in your shell profile:

```sh
export TEXINPUTS="$HOME/.local/share/nvim/lextern_ipe//:$TEXINPUTS"
```

(adjust the path if your `stdpath("data")` differs -- run `:lua print(vim.fn.stdpath("data"))`
to check). `:checkhealth lextern_ipe` verifies this is set up correctly.

Run `:DefineIncfig` to insert `\usepackage{lextern-ipe}` right after the
last `\usepackage` line, falling back to right after `\documentclass` if
there's no `\usepackage`, and to the cursor if there's neither
(`:DefineIncfig --cursor` always inserts at the cursor). `:AddFigure` and
`:InsertFigure` check whether `\incfig` is defined before inserting a
`\incfig{...}{}` line, and offer to run this for you if it doesn't look
defined -- covering `\usepackage{lextern-ipe}`, plain buffer text, *and*
(via `kpsewhich`, part of any TeX distribution) a `\documentclass`/
`\usepackage` you already load, up to `kpsewhich_depth` levels of
`\RequirePackage`/`\usepackage` indirection (default `2` -- covers e.g. a
custom `\documentclass` that itself does `\RequirePackage{lextern-ipe}`;
raise it if your `\incfig` is defined further down a require chain). The
same resolution applies to `\incfiglib`/`:AddFigure --lib` specifically,
not just `\incfig` in general. It's still a heuristic, so declining the
prompt remains a legitimate choice, not just a dismissal.

If you'd rather not depend on `TEXINPUTS` at all, you can skip
`\usepackage{lextern-ipe}` and define `\incfig` yourself instead -- the
plugin only ever checks whether it's defined, never how:

```latex
\usepackage{graphicx}

\newcommand{\incfig}[2]{%
    \begin{figure}[htbp]
        \centering
        \includegraphics[width=0.8\linewidth]{#1.pdf}
        \caption{#2}
        \label{fig:#1}
    \end{figure}
}
```

Note this opts out of the [figure library](#figure-library), which needs
`\incfiglib` from the generated package specifically.

## Figure stylesheets

Ipe renders the text in a figure with pdflatex, using only the stylesheets
embedded in that figure's `.ipe` file -- by default just Ipe's "basic" sheet,
which has no preamble. If your figures need the same fonts and macros as your
document (say `\mathbb`, `\bm`, a custom `\vec`), the fix is a stylesheet with
a `<preamble>` element, embedded in each figure. A starter is included at
`templates/preamble.isy`:

```xml
<ipestyle name="lextern-preamble">
<preamble>
\usepackage{amsmath,amssymb,amsthm}
% Add your own packages and macros below:
</preamble>
</ipestyle>
```

**New figures.** Save the sheet somewhere stable -- `~/.ipe/styles/` is Ipe's
own user style directory, which also lets Ipe find it by name later -- and
list it in `setup()`:

```lua
stylesheets = { "~/.ipe/styles/lextern-preamble.isy" },
```

`:AddFigure` embeds every listed sheet into the figure right after the basic
one (Ipe cascades sheets in order, so yours takes precedence). Any number of
sheets works, including Ipe's own shipped ones from `/usr/share/ipe/*/styles/`.
`:checkhealth lextern_ipe` verifies each listed file exists and is a
stylesheet.

**Existing figures.** Sheets are baked into the file at creation, so a figure
made before you changed `stylesheets` (or the preamble in it) doesn't pick up
the change. Update it from inside Ipe:

- To add the sheet: *Edit > Style sheets*, *Add*, pick the `.isy` file, save.
- To reload a sheet already embedded, after editing the file: *Edit > Update
  style sheets* (`Ctrl+Shift+U`), then save. Ipe looks the sheet up *by name*
  (`lextern-preamble.isy`) in the figure's own directory, then in
  `~/.ipe/styles/`, which is why that location is recommended above.

Saving in Ipe triggers the watcher's PDF export as usual.

**About `IPESTYLES`.** Earlier versions of this README suggested pointing the
`IPESTYLES` environment variable at a stylesheet file. That doesn't work: Ipe
reads `IPESTYLES` as a colon-separated list of style *directories* that
replaces its default search path (`~/.ipe/styles/` plus the system styles;
use `_` for the latter), and even then it only affects *File > New* and the
lookups above, never a figure opened from disk. If you have it set,
`:checkhealth lextern_ipe` warns about entries that aren't directories.

## Figure library

Alongside each document's own `<basename>_figures` dir, there's a single
shared library (`library_dir`, default `stdpath("data")/lextern_ipe/library`)
for figures you want to reuse across documents. Add `--lib` to target it
instead of the current file's own figures dir:

| Command | Targets |
|---|---|
| `:AddFigure --lib` | Create a new figure in the library |
| `:EditFigure --lib` | Pick and edit an existing library figure |
| `:InsertFigure --lib` | Pick a library figure and insert its `\incfiglib` at cursor |

Library figures are referenced as `\incfiglib{name}{caption}` rather than
by a path relative to the current file, so the reference stays valid
regardless of where the `.tex` file itself lives. `\incfiglib` is defined in
the generated package:

```latex
\newcommand{\incfiglib}[2]{%
    \begin{figure}[htbp]
        \centering
        \includegraphics[width=0.8\linewidth]{\incfiglibrary/#1.pdf}
        \caption{#2}
        \label{fig:lib:#1}
    \end{figure}
}
```

`\incfiglibrary` is the library path, appended to the package from your
`library_dir` every time `setup()` runs, so moving the library later is a
one-line config change, not a find-and-replace across every document. The
label is `fig:lib:<name>`, so `\ref{fig:lib:free-body-diagram}` -- the
library's absolute path never ends up in a label. `\renewcommand` it in your
document if you want a different layout. (Documents from before `\incfiglib`
existed, which reference `\incfig{\incfiglibrary/name}{}`, keep compiling.)

## Commands

| Command | Description |
|---|---|
| `:AddFigure` | Prompt for a name, create `.ipe` file, insert `\incfig` at cursor, open IPE, start watcher (`:AddFigure --lib` targets the library) |
| `:DefineIncfig` | Insert `\usepackage{lextern-ipe}` after the last `\usepackage` line, or `\documentclass`/cursor as fallbacks (`:DefineIncfig --cursor` to always insert at cursor) |
| `:EditFigure` | Pick an existing figure and open it in IPE (`:EditFigure --lib` for the library) |
| `:InsertFigure` | Pick an existing figure and insert its `\incfig` at cursor (`:InsertFigure --lib` inserts `\incfiglib` for a library figure) |
| `:StartWatcher` | Manually start the file watcher for the current file's figures dir |
| `:StopWatcher` | Stop every active watcher (per-file and library alike) |
| `:WatcherStatus` | Show every active watcher and its export count |

### Suggested keymaps

| Keymap | Command |
|---|---|
| `<leader>fa` | `:AddFigure` |
| `<leader>fe` | `:EditFigure` |
| `<leader>fi` | `:InsertFigure` |

## Workflow

1. Open a `.tex` file, say `test.tex`, and run `:AddFigure`.
2. Enter a name (e.g. "Free Body Diagram") at the prompt.
3. The plugin creates `test_figures/free-body-diagram.ipe`, inserts
   `\incfig{test_figures/free-body-diagram}{}` at your cursor, exports an
   empty `free-body-diagram.pdf` so the document already compiles, and
   opens IPE.
4. Draw your figure. Every save triggers a PDF export. With `latexmk -pvc`,
   your document recompiles automatically.
5. Fill in the caption: the cursor is left on the closing brace of the
   second `\incfig` argument, so `i` types straight into it.

## File organization

Per-file figures are stored in a directory derived from the `.tex` filename
(e.g. `foo.tex` → `foo_figures/`), next to the document itself. This keeps
figures separated per document and makes it easy to move a `.tex` file along
with its figures. Figures meant to be shared across documents instead go in
the [library](#figure-library) (`library_dir`), referenced by name via
`\incfiglib` rather than by colocation.
