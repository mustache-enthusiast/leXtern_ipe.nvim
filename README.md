# leXtern_ipe.nvim

Neovim plugin for seamless [IPE](https://ipe.otfried.org/) figure integration with LaTeX documents.

Create, edit, and insert IPE figures from within Neovim with a couple of keystrokes. A built-in file watcher automatically exports figures to PDF on save, so your LaTeX document recompiles instantly.

## Requirements

- **Neovim** >= 0.10
- **IPE** drawing editor (`ipe` and `ipetoipe` on PATH)
- **rofi** for figure name input and selection
- **Hyprland** (optional, for floating IPE window)

### Arch Linux

```zsh
paru -S ipe rofi
```

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "YOUR_USERNAME/leXtern_ipe.nvim",
  ft = "tex",
  config = function()
    require("lextern_ipe").setup()
  end,
}
```

Or any plugin manager that adds the repo to your runtime path.

## Configuration

All options are optional. Pass them to `setup()`:

```lua
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
```

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

## IPE preamble stylesheet

To match fonts and macros between your LaTeX document and IPE figures, create a
stylesheet and point IPE to it via the `IPESTYLES` environment variable:

```zsh
export IPESTYLES="$HOME/.config/ipe/lextern-preamble.isy"
```

A starter stylesheet is included at `templates/preamble.isy`. Copy it and add
your packages:

```xml
<ipestyle name="lextern-preamble">
<preamble>
\usepackage{amsmath,amssymb,amsthm}
\usepackage{physics}
% your macros here
</preamble>
</ipestyle>
```

## Usage

### Commands

| Command | Description |
|---|---|
| `:AddFigure` | Create a new figure: prompts for name, creates `.ipe` file, inserts `\incfig` at cursor, opens IPE, starts watcher |
| `:EditFigure` | Pick an existing figure from rofi and open it in IPE |
| `:InsertFigure` | Pick an existing figure and insert its `\incfig` at cursor |
| `:StartWatcher` | Manually start the file watcher |
| `:StopWatcher` | Stop the file watcher |
| `:WatcherStatus` | Show watcher state |

### Suggested keybindings

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "tex",
  callback = function()
    vim.keymap.set("n", "<leader>fa", "<cmd>AddFigure<cr>", { buffer = true, desc = "Add IPE figure" })
    vim.keymap.set("n", "<leader>fe", "<cmd>EditFigure<cr>", { buffer = true, desc = "Edit IPE figure" })
    vim.keymap.set("n", "<leader>fi", "<cmd>InsertFigure<cr>", { buffer = true, desc = "Insert IPE figure" })
  end,
})
```

### Workflow

1. Open a `.tex` file in Neovim.
2. Run `:AddFigure` — rofi prompts for a name (e.g. "Free Body Diagram").
3. The plugin sanitizes the name (`free-body-diagram`), creates
   `test_figures/free-body-diagram.ipe`, inserts
   `\incfig{test_figures/free-body-diagram}{}` at your cursor, and opens IPE.
4. Draw your figure in IPE. Every time you save, the watcher runs `ipetoipe`
   to export the PDF. If you're running `latexmk -pvc`, your document
   recompiles automatically.
5. Fill in the caption in the second `\incfig` argument when ready.

### File organization

Figures are stored in a directory derived from the `.tex` filename:

```
project/
├── lecture-01.tex
├── lecture-01_figures/
│   ├── free-body-diagram.ipe
│   └── free-body-diagram.pdf
├── lecture-02.tex
└── lecture-02_figures/
    ├── circuit.ipe
    └── circuit.pdf
```

This makes it easy to move a `.tex` file along with its figures.

## License

MIT
