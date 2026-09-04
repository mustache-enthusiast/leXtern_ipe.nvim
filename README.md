# leXtern_ipe.nvim

Draw [Ipe](https://ipe.otfried.org/) figures for LaTeX documents without
leaving Neovim. One command creates the figure, drops a labelled `figure`
environment at the cursor, and opens Ipe; every save in Ipe exports the PDF,
so `latexmk -pvc` picks it up immediately.

> **Disclosure:** this plugin was built with AI assistance (Claude Code). The
> design, review, and testing were directed by a human; the commit history
> shows where each piece came from.

## Requirements

- Neovim 0.10 or newer
- [Ipe](https://ipe.otfried.org/) 7.2 or newer, with `ipe` and `ipetoipe` on
  `PATH`
- A TeX distribution. `kpsewhich` (part of any) is optional but recommended;
  it lets the plugin see that your document class or packages already load
  `graphicx`.

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

Your documents need `\usepackage{graphicx}`, which the plugin offers to add
when it isn't there. That's all, unless you want the shared
[figure library](#figure-library) — that one needs the plugin's generated
LaTeX package on `TEXINPUTS`, added once in your shell profile:

```sh
export TEXINPUTS="$HOME/.local/share/nvim/lextern_ipe//:$TEXINPUTS"
```

Run `:checkhealth lextern_ipe` to confirm the executables, `TEXINPUTS`, and
your configuration.

## Quick start

1. Open `notes.tex` and run `:AddFigure`.
2. Enter a name, say `Free Body Diagram`.
3. The plugin creates `notes_figures/free-body-diagram.ipe`, inserts this
   at the cursor, exports an empty PDF so the document already compiles,
   and opens Ipe:

   ```latex
   \begin{figure}[htbp]
       \centering
       \includegraphics[width=0.8\linewidth]{notes_figures/free-body-diagram.pdf}
       \caption{}
       \label{fig:free-body-diagram}
   \end{figure}
   ```

   If `\includegraphics` isn't available yet it offers to add
   `\usepackage{graphicx}` first.
4. Draw. Each save in Ipe re-exports the PDF.
5. Back in Neovim the cursor is on the caption's closing brace, so `i` types
   straight into it. Everything about the figure is right there in the
   document — change the width, the placement, the label.

Figures live in `<document>_figures/` next to the `.tex` file, so a document
and its figures move together. Figures shared between documents go in the
[library](#figure-library).

## Commands

| Command | Action |
|---|---|
| `:AddFigure` | Prompt for a name, create the figure, insert its `figure` environment, open Ipe, start the watcher |
| `:EditFigure` | Pick an existing figure and open it in Ipe |
| `:InsertFigure` | Pick an existing figure and insert its `figure` environment at the cursor |
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

  -- Prompt before inserting \usepackage{graphicx} when \includegraphics
  -- isn't available (:AddFigure/:InsertFigure): "ask", "always", "never"
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
  -- whether a loaded class or package brings in graphicx (kpsewhich).
  -- 2 finds \RequirePackage{graphicx} inside a custom class; 0 checks
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

A figure this plugin inserts is an ordinary `figure` environment, so a
document needs one thing: `\usepackage{graphicx}`.

Before inserting, the plugin looks for it in the buffer and, via
`kpsewhich`, inside any class or package the document loads, following
`\RequirePackage` chains up to `kpsewhich_depth` levels. Comments are
ignored. If it can't find it, it offers to add the line — it's a heuristic,
so declining the prompt is a legitimate answer.

Figures are labelled after their name: `notes_figures/flux.ipe` is
`\ref{fig:flux}`, and a library figure `gamma` is `\ref{fig:lib:gamma}`. The
label lives in the document, so you can change it — see [Labels](#labels).

### The generated package

`setup()` also generates a small package, `lextern-ipe.sty`, in
`stdpath("data")/lextern_ipe/`. Only [library](#figure-library) figures need
it, for `\incfiglibrary`; a document's own figures need nothing from it. The
`TEXINPUTS` line from [Installation](#installation) is what lets
`\usepackage{lextern-ipe}` find it. If your `stdpath("data")` isn't
`~/.local/share/nvim`, adjust the path (`:lua print(vim.fn.stdpath("data"))`).
`:checkhealth` confirms the package resolves.

It also defines two macros the plugin no longer inserts, kept so that
documents written against them keep compiling:

- `\incfig{path}{caption}`: the same `figure` environment, labelled
  `fig:name` after the last path component.
- `\incfiglib{name}{caption}`: the same for a library figure, labelled
  `fig:lib:name`.

`:LabelFigure` expands an `\incfig` call into the environment it stands for,
which is how you migrate one when you want to change its label.

> **Upgrading:** two things changed. Figures are now inserted as `figure`
> environments rather than `\incfig` lines, and labels no longer include the
> directory (`fig:notes_figures/flux` is now `fig:flux`). Existing documents
> keep working — `\incfig` is still defined — but their labels change with
> the package, so either update those `\ref`s or pin the old scheme with your
> own `\newcommand{\incfig}`:
>
> ```latex
> \usepackage{graphicx}
> \newcommand{\incfig}[2]{%
>     \begin{figure}[htbp]
>         \centering
>         \includegraphics[width=0.8\linewidth]{#1.pdf}
>         \caption{#2}
>         \label{fig:#1}
>     \end{figure}
> }
> ```

## Labels

Figures are labelled after their name, which is usually what you want and
occasionally isn't: `\ref{fig:diagram-3}` says nothing about what the diagram
is. `:LabelFigure` picks a figure the same way `:EditFigure` does, asks for a
label, and rewrites the figure's `\label` to that.

- A bare name gets the `fig:` prefix (`gauss` → `fig:gauss`); anything with
  a prefix of its own (`eq:gauss`) is taken as written.
- `\ref`, `\autoref`, `\cref` and friends pointing at the old label are
  updated in the current buffer, including inside `\cref{a,b}` lists. Other
  files in a multi-file project are not touched.
- If a document includes the same figure twice, the one nearest the cursor
  is labelled, and you're told about the other. (Inserting a figure twice
  gives both copies the same label, which `:LabelFigure` is how you fix; the
  plugin says so at the time.)
- A label already used by another `\label` is a warning, not a refusal.

Run on a legacy `\incfig{path}{caption}` line, it expands the call into the
figure environment it stands for, with the label written out, keeping the
caption, the indentation and any comment on the line.

## Figure library

One shared directory, `library_dir`, for figures reused across documents.
Add `--lib` to `:AddFigure`, `:EditFigure`, `:InsertFigure`, or
`:LabelFigure` to target it.

A library figure is included through `\incfiglibrary`, which `setup()` sets
to your current `library_dir`, so moving the library is a config change
rather than an edit to every document. It's labelled `fig:lib:name`, keeping
it distinct from a document's own figure of the same name:

```latex
\begin{figure}[htbp]
    \centering
    \includegraphics[width=0.8\linewidth]{\incfiglibrary/gamma.pdf}
    \caption{}
    \label{fig:lib:gamma}
\end{figure}
```

`\incfiglibrary` is the one thing a document does need from the generated
package, so `--lib` commands offer to add `\usepackage{lextern-ipe}` when
it isn't loaded (`confirm_missing_library_package`), and this is what the
`TEXINPUTS` line from [Installation](#installation) is for.

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
