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

      -- Debounce interval for the file watcher (ms)
      debounce_ms = 100,

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

The `\incfig` command needs to be defined in your document preamble (or a
shared `.sty` file) before you can use it. Run `:DefineIncfig` to insert it
right after the last `\usepackage` line (or `:DefineIncfig!` to insert at
the cursor instead), or add it by hand:

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

`:AddFigure` and `:InsertFigure` check whether `\incfig` is defined before
inserting a `\incfig{...}{}` line. If it doesn't look defined, they'll ask
whether to insert the preamble for you (via `:DefineIncfig`'s default
placement) before continuing. This check isn't just buffer text: it also
resolves any `\documentclass`/`\usepackage` names through `kpsewhich` (part
of any TeX distribution) and scans those files directly, so a custom
`.cls`/`.sty` that defines `\incfig` itself is recognized and you won't be
asked every time. It's still a heuristic — a package that defines `\incfig`
indirectly via a package *it* requires won't be found — so declining the
prompt is a legitimate choice, not just a dismissal.

## Commands

| Command | Description |
|---|---|
| `:AddFigure` | Prompt for a name, create `.ipe` file, insert `\incfig` at cursor, open IPE, start watcher |
| `:DefineIncfig` | Insert the `\incfig` macro after the last `\usepackage` line (`:DefineIncfig!` to insert at cursor instead) |
| `:EditFigure` | Pick an existing figure and open it in IPE |
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
2. Enter a name (e.g. "Free Body Diagram") at the prompt.
3. The plugin creates `test_figures/free-body-diagram.ipe`, inserts
   `\incfig{test_figures/free-body-diagram}{}` at your cursor, and opens IPE.
4. Draw your figure. Every save triggers a PDF export. With `latexmk -pvc`,
   your document recompiles automatically.
5. Fill in the caption in the second `\incfig` argument.

## File organization

Figures are stored in a directory derived from the `.tex` filename
(e.g. `foo.tex` → `foo_figures/`). This keeps figures separated per document
and makes it easy to move a `.tex` file along with its figures.
