# leXtern_ipe.nvim

Neovim plugin for seamless [IPE](https://ipe.otfried.org/) figure integration with LaTeX documents.

Create, edit, and insert IPE figures from within Neovim with a couple of keystrokes. A built-in file watcher automatically exports figures to PDF on save, so your LaTeX document recompiles instantly.

## Dependencies

- **Neovim** >= 0.10
- **IPE** drawing editor (`ipe` and `ipetoipe` must be on PATH)
- **rofi** for figure name input and selection
- **Hyprland** (optional, only required for floating IPE window)

## Setup

Lazy.nvim:
```lua
{
  "mustache-enthusiast/leXtern_ipe.nvim",
  ft = "tex",
  config = function()
    require("lextern_ipe").setup({
      -- How to handle missing figures directory: "ask", "always", "never"
      dir_create_mode = "ask",

      -- Extra flags passed to rofi (e.g. "-theme my-theme")
      rofi_opts = "",

      -- Debounce interval for the file watcher (ms)
      debounce_ms = 100,

      -- Open IPE in a floating window (requires Hyprland)
      floating = false,

      -- Floating window size in pixels (only used when floating = true)
      float_width = 900,
      float_height = 700,
    })
  end,
}
```

All config options are optional and the defaults are shown above.

## LaTeX setup

Add the `\incfig` command to your document preamble (or a shared `.sty` file):

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

By default, IPE renders text in figures using its own basic preamble. If you
need your figures to use the same fonts and macros as your document, point IPE
to a custom stylesheet via `export IPESTYLES="path/to/stylesheet.isy"`. A
starter stylesheet is included at `templates/preamble.isy`.

## Commands

| Command | Description |
|---|---|
| `:AddFigure` | Prompt for a name, create `.ipe` file, insert `\incfig` at cursor, open IPE, start watcher |
| `:EditFigure` | Pick an existing figure via rofi and open it in IPE |
| `:InsertFigure` | Pick an existing figure and insert its `\incfig` at cursor |
| `:StartWatcher` | Manually start the file watcher |
| `:StopWatcher` | Stop the file watcher |
| `:WatcherStatus` | Show watcher state |

### Suggested keymaps

| Keymap | Command |
|---|---|
| `<leader>fa` | `:AddFigure` |
| `<leader>fe` | `:EditFigure` |
| `<leader>fi` | `:InsertFigure` |

## Workflow

1. Open a `.tex` file and run `:AddFigure`.
2. Rofi prompts for a name (e.g. "Free Body Diagram").
3. The plugin creates `test_figures/free-body-diagram.ipe`, inserts
   `\incfig{test_figures/free-body-diagram}{}` at your cursor, and opens IPE.
4. Draw your figure. Every save triggers a PDF export. With `latexmk -pvc`,
   your document recompiles automatically.
5. Fill in the caption in the second `\incfig` argument.

## File organization

Figures are stored in a directory derived from the `.tex` filename
(e.g. `foo.tex` → `foo_figures/`). This keeps figures separated per document
and makes it easy to move a `.tex` file along with its figures.
