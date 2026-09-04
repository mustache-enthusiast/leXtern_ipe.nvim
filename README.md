# leXtern_ipe.nvim

Draw [Ipe](https://ipe.otfried.org/) figures for LaTeX documents without
leaving Neovim. One command creates the figure, drops an `\incfig` line at
the cursor, and opens Ipe; every save in Ipe exports the PDF, so
`latexmk -pvc` picks it up immediately.

> **Disclosure:** this plugin was built with AI assistance (Claude Code). The
> design, review, and testing were directed by a human; the commit history
> shows where each piece came from.

## Requirements

- Neovim 0.10 or newer
- [Ipe](https://ipe.otfried.org/) 7.2 or newer, with `ipe` and `ipetoipe` on
  `PATH`
- A TeX distribution. `kpsewhich` (part of any) is optional but recommended;
  it lets the plugin see `\incfig` definitions inside your document class or
  packages.

Prompts use `vim.ui.input` and `vim.ui.select`, so a UI provider such as
[dressing.nvim](https://github.com/stevearc/dressing.nvim) or
[telescope-ui-select](https://github.com/nvim-telescope/telescope-ui-select.nvim)
is picked up automatically.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "mustache-enthusiast/leXtern_ipe.nvim",
  ft = "tex",
  keys = {
    { "<leader>fa", "<cmd>AddFigure<cr>",    ft = "tex", desc = "Add Ipe figure" },
    { "<leader>fe", "<cmd>EditFigure<cr>",   ft = "tex", desc = "Edit Ipe figure" },
    { "<leader>fi", "<cmd>InsertFigure<cr>", ft = "tex", desc = "Insert Ipe figure" },
    { "<leader>fl", "<cmd>LabelFigure<cr>",  ft = "tex", desc = "Label Ipe figure" },
  },
  config = function()
    require("lextern_ipe").setup({}) -- see Configuration
  end,
}
```

Then, once, add the plugin's generated LaTeX package to `TEXINPUTS` in your
shell profile (details under [LaTeX setup](#latex-setup)):

```sh
export TEXINPUTS="$HOME/.local/share/nvim/lextern_ipe//:$TEXINPUTS"
```

Run `:checkhealth lextern_ipe` to confirm the executables, `TEXINPUTS`, and
your configuration.

## Quick start

1. Open `notes.tex` and run `:AddFigure`.
2. Enter a name, say `Free Body Diagram`.
3. The plugin creates `notes_figures/free-body-diagram.ipe`, inserts
   `\incfig{notes_figures/free-body-diagram}{}` at the cursor, exports an
   empty PDF so the document already compiles, and opens Ipe. If `\incfig`
   isn't defined yet it offers to add `\usepackage{lextern-ipe}` first.
4. Draw. Each save in Ipe re-exports the PDF.
5. Back in Neovim the cursor is on the caption's closing brace, so `i` types
   straight into it. The figure is `\ref{fig:free-body-diagram}`, or
   whatever you rename it to with `:LabelFigure`.

Figures live in `<document>_figures/` next to the `.tex` file, so a document
and its figures move together. Figures shared between documents go in the
[library](#figure-library).

## Commands

| Command | Action |
|---|---|
| `:AddFigure` | Prompt for a name, create the figure, insert `\incfig`, open Ipe, start the watcher |
| `:EditFigure` | Pick an existing figure and open it in Ipe |
| `:InsertFigure` | Pick an existing figure and insert its `\incfig` at the cursor |
| `:LabelFigure` | Pick a figure and give it a `\label` of your own, updating references to the old one |
| `:DefineIncfig` | Insert `\usepackage{lextern-ipe}` after the last `\usepackage` (or after `\documentclass`, or at the cursor) |
| `:StartWatcher` | Start the PDF export watcher for this document's figures dir |
| `:StopWatcher` | Stop every watcher |
| `:WatcherStatus` | List active watchers and their export counts |

Flags: `--lib` on `:AddFigure`, `:EditFigure`, `:InsertFigure`, and
`:LabelFigure` targets the [library](#figure-library) instead of the
document's own figures dir.
`--cursor` on `:DefineIncfig` always inserts at the cursor.

## Configuration

Every option is optional. The defaults:

```lua
require("lextern_ipe").setup({
  -- Create a missing figures directory: "ask", "always", "never"
  dir_create_mode = "ask",

  -- Prompt before inserting \usepackage{lextern-ipe} when \incfig isn't
  -- defined (:AddFigure/:InsertFigure): "ask", "always", "never"
  confirm_missing_preamble = "ask",

  -- Prompt before :DefineIncfig inserts a second definition
  confirm_duplicate_preamble = "ask",

  -- Prompt before --lib commands insert \usepackage{lextern-ipe}
  confirm_missing_library_package = "ask",

  -- Shared figure library (see "Figure library"). ~ is expanded. Avoid
  -- spaces, # and %: the path is used inside \includegraphics.
  library_dir = vim.fn.stdpath("data") .. "/lextern_ipe/library",

  -- Ipe stylesheets (.isy) embedded into every new figure, e.g. one
  -- carrying your document's preamble (see "Figure stylesheets")
  stylesheets = {},

  -- How far to follow \RequirePackage/\usepackage chains when checking
  -- whether \incfig is defined by a loaded class or package (kpsewhich).
  -- 2 finds \RequirePackage{lextern-ipe} inside a custom class; 0 checks
  -- only the buffer text.
  kpsewhich_depth = 2,

  -- Wait this long after the last write before exporting (ms)
  debounce_ms = 100,

  -- Open Ipe as a centered floating window (Hyprland; see below)
  floating = false,
  float_size = { 800, 900 },

  -- Or launch Ipe yourself: function(filepath). Overrides `floating`.
  launch_cmd = nil,
})
```

`:checkhealth lextern_ipe` validates every value and warns about option
names it doesn't recognize.

## LaTeX setup

`setup()` generates a small package, `lextern-ipe.sty`, in
`stdpath("data")/lextern_ipe/`. It provides:

- `\incfig{path}{caption}`: a centered `figure` with
  `\includegraphics[width=0.8\linewidth]{path.pdf}`, labelled `fig:name`
  after the last path component — `\incfig{notes_figures/flux}{}` is
  `\ref{fig:flux}`. Defined with `\providecommand`, so your own definition
  wins if you have one.
- `\incfiglib{name}{caption}`: the same for a [library](#figure-library)
  figure, labelled `fig:lib:name`.

The directory is left out of the label deliberately: every `\incfig` in a
document draws from that document's own `<basename>_figures/`, so the path
would disambiguate nothing. `:LabelFigure` replaces the derived label
with one of your own — see [Labels](#labels).

> **Upgrading:** labels used to include the directory
> (`fig:notes_figures/flux`). If you have documents written against that,
> either update their `\ref`s or keep the old scheme with your own
> `\newcommand{\incfig}` — see below.

The `TEXINPUTS` line from [Installation](#installation) is what lets
`\usepackage{lextern-ipe}` find it. If your `stdpath("data")` isn't
`~/.local/share/nvim`, adjust the path (`:lua print(vim.fn.stdpath("data"))`).
`:checkhealth` confirms the package resolves.

**How the check works.** Before inserting an `\incfig` line, the plugin
looks for a definition in the buffer, in `\usepackage{lextern-ipe}`, and,
via `kpsewhich`, inside any class or package the document loads, following
`\RequirePackage` chains up to `kpsewhich_depth` levels. Comments are
ignored. It's a heuristic, so declining the prompt is a legitimate answer.

**Defining `\incfig` yourself.** If you'd rather not touch `TEXINPUTS`, put
this in your preamble or class instead. The plugin only checks that
`\incfig` exists, never how it's defined. This does opt out of the library,
which needs `\incfiglib` from the package. The version below labels by
path, `fig:notes_figures/flux`; `:LabelFigure` works either way, since it
writes the label out in full.

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

## Labels

`\incfig` works its label out from the path, which is fine until it isn't:
`\ref{fig:diagram-3}` says nothing about what the diagram is. `:LabelFigure`
picks a figure the same way `:EditFigure` does, asks for a label, and gives
the figure that one instead.

The macro takes no label argument — it can't, without breaking every
document that defines its own `\incfig` — so the call is expanded into the
figure environment it stood for, with the `\label` written out:

```latex
\incfig{notes_figures/flux}{Flux through a closed surface}
```

becomes

```latex
\begin{figure}[htbp]
    \centering
    \includegraphics[width=0.8\linewidth]{notes_figures/flux.pdf}
    \caption{Flux through a closed surface}
    \label{fig:gauss}
\end{figure}
```

That environment is exactly what `\incfig` expands to, so nothing about the
figure changes except the label. Everything else follows:

- A bare name gets the `fig:` prefix (`gauss` → `fig:gauss`); anything with
  a prefix of its own (`eq:gauss`) is taken as written.
- `\ref`, `\autoref`, `\cref` and friends pointing at the old label are
  updated in the current buffer, including inside `\cref{a,b}` lists. Other
  files in a multi-file project are not touched.
- Run it again on an expanded figure and it just rewrites the `\label`;
  the environment isn't expanded twice.
- Indentation and any comments on the `\incfig` line are kept.
- If a document includes the same figure twice, the one nearest the cursor
  is labelled, and you're told about the other.
- A label already used by another `\label` is a warning, not a refusal.

`:LabelFigure` only labels a figure the buffer already includes —
`:InsertFigure` is what adds one.

## Figure library

One shared directory, `library_dir`, for figures reused across documents.
Add `--lib` to `:AddFigure`, `:EditFigure`, or `:InsertFigure` to target it.

Library figures are referenced by name, `\incfiglib{name}{caption}`, and
labelled `fig:lib:name`. The package defines `\incfiglib` in terms of
`\incfiglibrary`, which `setup()` sets to your current `library_dir`, so
moving the library is a config change rather than an edit to every document.
`\renewcommand{\incfiglib}` in your preamble to change the layout.

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

## Figure stylesheets

Ipe renders figure text with pdflatex using only the stylesheets embedded in
the `.ipe` file, and the default "basic" sheet has no preamble. To give
figures your document's fonts and macros, embed a sheet with a `<preamble>`.
A starter ships as `templates/preamble.isy`:

```xml
<ipestyle name="lextern-preamble">
<preamble>
\usepackage{amsmath,amssymb,amsthm}
% Add your own packages and macros below:
</preamble>
</ipestyle>
```

Save it to `~/.ipe/styles/lextern-preamble.isy` (Ipe's own user style
directory) and list it:

```lua
stylesheets = { "~/.ipe/styles/lextern-preamble.isy" },
```

New figures get every listed sheet embedded after the basic one, so yours
takes precedence. Ipe's shipped sheets in `/usr/share/ipe/*/styles/` work
too.

Existing figures keep the sheets they were created with. To add a sheet to
one, open it and use *Edit > Style sheets > Add*. After editing a sheet that
is already embedded, *Edit > Update style sheets* (`Ctrl+Shift+U`) reloads
it by name from the figure's directory or `~/.ipe/styles/`. Save, and the
watcher exports as usual.

`IPESTYLES` is not the way to do this: Ipe reads it as a list of style
*directories* replacing its search path, and it never affects a figure
opened from disk. `:checkhealth` warns if it points at a file.

## Floating Ipe window (Hyprland)

`floating = true` opens Ipe as a centered floating window of `float_size`.
Hyprland is configured in Lua since 0.55, and `hyprctl eval` runs Lua inside
the compositor, so the plugin evaluates the same call a `hyprland.lua` would:

```lua
hl.exec_cmd("ipe '/path/to/figure.ipe'", { float = true, size = "800 900", center = true })
```

Everything Hyprland-specific is in `lua/lextern_ipe/hyprland.lua`, so an API
change is one edit there. The old `hyprctl dispatch exec "[float;...]"`
string form is not used; on 0.56 it is already a syntax error. Verified
against Hyprland 0.56.2.

To float every Ipe window regardless of how it was started, a window rule in
`~/.config/hypr/hyprland.lua` does the same job with `floating` left off:

```lua
hl.window_rule({
    name   = "ipe-float",
    match  = { class = "ipe" },
    float  = true,
    size   = { 800, 900 },
    center = true,
})
```

On other compositors, use `launch_cmd`.

## Development

```sh
make test              # every tests/test_*.lua, each in its own headless Neovim
make test T=watcher    # one file
make test-live         # also the checks that open real windows (Hyprland)
```

Tests run with isolated `XDG_*` directories and a temporary working
directory, so they never touch your real config or data. Tests that need a
tool that isn't installed (`ipetoipe`, `kpsewhich`, `pdflatex`) skip
themselves. `tests/helpers.lua` documents the small `T` helper API.

## License

[MIT](LICENSE)
