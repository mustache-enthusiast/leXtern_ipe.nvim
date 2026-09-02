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

      -- Whether :AddFigure!/:InsertFigure! prompt before auto-inserting
      -- \usepackage{lextern-ipe} (which provides \incfiglibrary) when
      -- it isn't loaded yet: "ask", "always", "never"
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
file) and `\incfiglibrary` (see [Figure library](#figure-library) below).

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
(`:DefineIncfig!` always inserts at the cursor). `:AddFigure` and
`:InsertFigure` check whether `\incfig` is defined before inserting a
`\incfig{...}{}` line, and offer to run this for you if it doesn't look
defined -- covering `\usepackage{lextern-ipe}`, plain buffer text, *and*
(via `kpsewhich`, part of any TeX distribution) a `\documentclass`/
`\usepackage` you already load, up to `kpsewhich_depth` levels of
`\RequirePackage`/`\usepackage` indirection (default `2` -- covers e.g. a
custom `\documentclass` that itself does `\RequirePackage{lextern-ipe}`;
raise it if your `\incfig` is defined further down a require chain). The
same resolution applies to `\incfiglibrary`/`:AddFigure!` specifically, not
just `\incfig` in general. It's still a heuristic, so declining the prompt
remains a legitimate choice, not just a dismissal.

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
`\incfiglibrary` from the generated package specifically.

By default, IPE renders text in figures using its own basic preamble. If you
need your figures to use the same fonts and macros as your document, point IPE
to a custom stylesheet via `export IPESTYLES="path/to/stylesheet.isy"`. A
starter stylesheet is included at `templates/preamble.isy`.

## Figure library

Alongside each document's own `<basename>_figures` dir, there's a single
shared library (`library_dir`, default `stdpath("data")/lextern_ipe/library`)
for figures you want to reuse across documents. Add a `!` to target it
instead of the current file's own figures dir:

| Command | Targets |
|---|---|
| `:AddFigure!` | Create a new figure in the library |
| `:EditFigure!` | Pick and edit an existing library figure |
| `:InsertFigure!` | Pick a library figure and insert its `\incfig` at cursor |

Library figures are referenced as `\incfig{\incfiglibrary/name}{}` rather
than a path relative to the current file, so the reference stays valid
regardless of where the `.tex` file itself lives. `\incfiglibrary` always
resolves to the *current* `library_dir` at compile time (it's defined in the
generated package, not copied into your document), so moving the library
later is a one-line config change, not a find-and-replace across every
document that references it.

## Commands

| Command | Description |
|---|---|
| `:AddFigure` | Prompt for a name, create `.ipe` file, insert `\incfig` at cursor, open IPE, start watcher (`:AddFigure!` targets the library) |
| `:DefineIncfig` | Insert `\usepackage{lextern-ipe}` after the last `\usepackage` line, or `\documentclass`/cursor as fallbacks (`:DefineIncfig!` to always insert at cursor) |
| `:EditFigure` | Pick an existing figure and open it in IPE (`:EditFigure!` for the library) |
| `:InsertFigure` | Pick an existing figure and insert its `\incfig` at cursor (`:InsertFigure!` for the library) |
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

1. Open a `.tex` file and run `:AddFigure`.
2. Enter a name (e.g. "Free Body Diagram") at the prompt.
3. The plugin creates `test_figures/free-body-diagram.ipe`, inserts
   `\incfig{test_figures/free-body-diagram}{}` at your cursor, and opens IPE.
4. Draw your figure. Every save triggers a PDF export. With `latexmk -pvc`,
   your document recompiles automatically.
5. Fill in the caption in the second `\incfig` argument.

## File organization

Per-file figures are stored in a directory derived from the `.tex` filename
(e.g. `foo.tex` → `foo_figures/`), next to the document itself. This keeps
figures separated per document and makes it easy to move a `.tex` file along
with its figures. Figures meant to be shared across documents instead go in
the [library](#figure-library) (`library_dir`), referenced by absolute path
via `\incfiglibrary` rather than colocation.
