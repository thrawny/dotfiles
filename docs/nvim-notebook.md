# Jupyter Notebook Support in Neovim/LazyVim

Research findings for setting up Jupyter notebook functionality with specific requirements:
1. Python scripts with cell markers (`# %%`)
2. SQL cells with syntax highlighting
3. Execute cells in Neovim environment
4. Export to .ipynb format

Research date: 2025-01-24

## Recommended Solution: Molten.nvim Ecosystem

**Components:** Molten.nvim + Jupytext.nvim + NotebookNavigator.nvim

This is the most mature, feature-complete solution as of 2025.

### How It Addresses Requirements

| Requirement | Support | Details |
|-------------|---------|---------|
| Python `# %%` cell markers | ✅ Excellent | Via NotebookNavigator.nvim |
| SQL syntax highlighting | ⚠️ Partial | Requires treesitter injection + IPython magic |
| Execute cells in Neovim | ✅ Excellent | Via Jupyter kernels with rich output |
| Export to .ipynb | ✅ Native | Auto-conversion via Jupytext |

### Plugin Configuration

Create `lua/plugins/jupyter.lua`:

```lua
return {
  -- Main execution engine
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    ft = { "python", "markdown" },
    config = function()
      -- Molten configuration
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_win_max_height = 20
      vim.g.molten_auto_open_output = false
      vim.g.molten_wrap_output = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true

      -- Keymaps
      vim.keymap.set("n", "<leader>mi", ":MoltenInit<CR>", { desc = "Molten Init", silent = true })
      vim.keymap.set("n", "<leader>me", ":MoltenEvaluateOperator<CR>", { desc = "Evaluate Operator", silent = true })
      vim.keymap.set("n", "<leader>mr", ":MoltenReevaluateCell<CR>", { desc = "Re-eval Cell", silent = true })
      vim.keymap.set("v", "<leader>me", ":<C-u>MoltenEvaluateVisual<CR>gv", { desc = "Evaluate Visual", silent = true })
      vim.keymap.set("n", "<leader>mo", ":MoltenHideOutput<CR>", { desc = "Hide Output", silent = true })
      vim.keymap.set("n", "<leader>md", ":MoltenDelete<CR>", { desc = "Delete Cell", silent = true })
    end,
  },

  -- Image rendering
  {
    "3rd/image.nvim",
    opts = {
      backend = "kitty",
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
        },
      },
      max_width = 100,
      max_height = 12,
      max_width_window_percentage = nil,
      max_height_window_percentage = 50,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
    },
  },

  -- Jupytext for ipynb conversion
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    config = function()
      require("jupytext").setup({
        style = "hydrogen",  -- Uses # %% markers
        output_extension = "auto",
        force_ft = "python",
        custom_language_formatting = {},
      })
    end,
  },

  -- Cell navigation
  {
    "GCBallesteros/NotebookNavigator.nvim",
    dependencies = {
      "echasnovski/mini.comment",
      "benlubas/molten-nvim",
    },
    event = "VeryLazy",
    config = function()
      local nn = require("notebook-navigator")
      nn.setup({
        activate_hydra_keys = "<leader>h",
        repl_provider = "molten",
        cell_markers = {
          python = "# %%",
        },
        syntax_highlight = true,
        cell_highlight_group = "CursorLine",
      })

      -- Keymaps
      vim.keymap.set("n", "<leader>X", nn.run_cell, { desc = "Run Cell" })
      vim.keymap.set("n", "<leader>x", nn.run_and_move, { desc = "Run Cell & Move" })
      vim.keymap.set("n", "[h", function() nn.move_cell("u") end, { desc = "Cell Above" })
      vim.keymap.set("n", "]h", function() nn.move_cell("d") end, { desc = "Cell Below" })
      vim.keymap.set("n", "<leader>xa", nn.run_all_cells, { desc = "Run All Cells" })
    end,
  },
}
```

### System Dependencies

```bash
# Python dependencies
pip install pynvim jupyter_client jupytext ipython-sql sqlalchemy cairosvg pnglatex

# Terminal with image support (required for inline plots)
brew install kitty  # macOS
# Or use WezTerm as alternative
```

### SQL Cell Support

#### 1. IPython SQL Magic (for execution)

In your first cell:
```python
# %%
%load_ext sql

# %%sql
%%sql
SELECT * FROM users WHERE active = 1;

# %%
# Or with variable assignment
result = %sql SELECT * FROM products LIMIT 10;
result_df = result.DataFrame()
```

#### 2. Treesitter Injection (for syntax highlighting)

Create `after/queries/python/injections.scm`:

```scm
; extends

; Highlight SQL in triple-quoted strings
((string_content) @injection.content
  (#lua-match? @injection.content "^%s*SELECT")
  (#set! injection.language "sql"))

((string_content) @injection.content
  (#lua-match? @injection.content "^%s*INSERT")
  (#set! injection.language "sql"))

((string_content) @injection.content
  (#lua-match? @injection.content "^%s*UPDATE")
  (#set! injection.language "sql"))

((string_content) @injection.content
  (#lua-match? @injection.content "^%s*DELETE")
  (#set! injection.language "sql"))
```

### Workflow

1. Open `.ipynb` file → auto-converts to `.py` with `# %%` markers
2. Run `:MoltenInit python3` to start kernel
3. Use `<leader>X` to execute cells
4. View output in floating windows or inline
5. Save file → auto-converts back to `.ipynb` with output preserved

### Keybindings

| Key | Action |
|-----|--------|
| `<leader>mi` | Initialize Molten kernel |
| `<leader>X` | Run current cell |
| `<leader>x` | Run cell and move to next |
| `<leader>xa` | Run all cells |
| `[h` / `]h` | Move to previous/next cell |
| `<leader>mr` | Re-evaluate cell |
| `<leader>mo` | Hide output |
| `<leader>md` | Delete cell |

### Pros

- Most actively developed solution (2025)
- Excellent image rendering with Kitty terminal
- Full Jupyter kernel support (all magic commands work)
- Can send keyboard interrupts to stop running code
- Multiple kernels per buffer support
- Import/export notebook outputs
- Native Python files with `# %%` markers

### Cons

- Complex initial setup (multiple plugins required)
- Image rendering requires specific terminals (Kitty or WezTerm)
- SQL cell syntax highlighting requires manual treesitter configuration
- Remote plugin architecture requires understanding
- Learning curve for Jupyter kernel concepts

## Alternative: Quarto + Otter.nvim

**Best for:** Multi-language notebooks, publishing workflows, better SQL support

### How It Addresses Requirements

| Requirement | Support | Details |
|-------------|---------|---------|
| Python cell markers | ⚠️ Different format | Uses `.qmd` files instead of `# %%` |
| SQL syntax highlighting | ✅ Native | Built-in support |
| Execute cells | ✅ Good | Via vim-slime or molten |
| Export to .ipynb | ✅ Yes | Via `quarto convert` |

### Configuration

```lua
return {
  {
    "quarto-dev/quarto-nvim",
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      lspFeatures = {
        enabled = true,
        languages = { "python", "sql", "bash" },
        chunks = "curly",
        diagnostics = {
          enabled = true,
          triggers = { "BufWritePost" },
        },
        completion = {
          enabled = true,
        },
      },
      codeRunner = {
        enabled = true,
        default_method = "molten",
        ft_runners = {
          python = "molten",
          sql = "molten",
        },
      },
    },
  },
  {
    "jmbuhr/otter.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "neovim/nvim-lspconfig",
    },
    opts = {},
  },
}
```

### Quarto Document Format

```qmd
---
title: "My Analysis"
format: ipynb
---

## Python Cell
```{python}
import pandas as pd
df = pd.read_csv("data.csv")
df.head()
```

## SQL Cell
```{sql}
SELECT * FROM users WHERE active = true;
```
```

### Conversion

```bash
# Install Quarto CLI
brew install quarto

# Convert between formats
quarto convert notebook.ipynb  # → notebook.qmd
quarto convert notebook.qmd --to ipynb  # → notebook.ipynb
```

### Pros

- Excellent multi-language support (Python, R, Julia, SQL, Bash)
- Native SQL syntax highlighting and execution
- LSP support for code chunks via otter.nvim
- Publishing-ready output (HTML, PDF, ipynb)
- Simpler than pure molten setup
- Great documentation

### Cons

- Requires learning Quarto format (not pure Python)
- `.qmd` files instead of `.py` with `# %%`
- Requires Quarto CLI installation
- Less "native Python" feel
- SQL execution requires database connection setup

## Other Alternatives Considered

### Jupynium.nvim

Real Jupyter Notebook UI in browser, synced with Neovim.

**Status:** Alpha stage
**Pros:** Full rich output, real Jupyter interface
**Cons:** Unstable, requires Selenium, one-way sync only

### vim-jukit

Traditional Vim plugin with IPython/tmux splits.

**Status:** Stable but less active development
**Pros:** Simpler setup, works with Vim and Neovim
**Cons:** No SQL support, limited image rendering

### iron.nvim

Basic REPL interaction.

**Status:** Legacy, superseded by molten
**Pros:** Very simple
**Cons:** No images, no rich output, basic features only

## Comparison Matrix

| Feature | Molten + Jupytext | Quarto + Otter | Jupynium | vim-jukit | iron.nvim |
|---------|------------------|----------------|----------|-----------|-----------|
| Python `# %%` cells | ✅ Excellent | ⚠️ .qmd format | ✅ .ju.py files | ✅ Yes | ⚠️ Basic |
| SQL syntax highlight | ⚠️ Manual setup | ✅ Native | ✅ Native | ❌ No | ❌ No |
| Cell execution | ✅ Excellent | ✅ Good | ✅ Excellent | ✅ Good | ⚠️ Basic |
| ipynb export | ✅ Native | ✅ Via CLI | ✅ Native | ✅ Via jupytext | ❌ No |
| Image rendering | ✅ Excellent | ⚠️ External | ✅ Browser | ⚠️ Limited | ❌ No |
| Setup complexity | High | Medium | High | Low | Very Low |
| Maturity (2025) | ✅ Mature | ✅ Mature | ⚠️ Alpha | ✅ Stable | ✅ Stable |
| Active development | ✅ Very active | ✅ Active | ⚠️ Limited | ⚠️ Slow | ⚠️ Minimal |

## Decision Factors

Choose **Molten.nvim** if:
- You want native Python files with `# %%` markers
- You need inline image rendering in terminal
- You're comfortable with complex setup
- You use Kitty or WezTerm terminal

Choose **Quarto** if:
- You work with multiple languages (R, Julia, SQL)
- You want better SQL support
- You're creating publishable documents
- You're okay with `.qmd` format

Choose **Jupynium** if:
- You need full Jupyter UI features
- You're willing to use alpha software
- You want interactive widgets in browser

## Resources

### Documentation
- [Molten.nvim](https://github.com/benlubas/molten-nvim)
- [Jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim)
- [NotebookNavigator.nvim](https://github.com/GCBallesteros/NotebookNavigator.nvim)
- [Quarto Neovim](https://quarto.org/docs/tools/neovim.html)
- [Otter.nvim](https://github.com/jmbuhr/otter.nvim)

### Guides
- [Molten Notebook Setup](https://github.com/benlubas/molten-nvim/blob/main/docs/Notebook-Setup.md)
- [Jupytext Format Docs](https://jupytext.readthedocs.io/en/latest/formats-scripts.html)
- [IPython SQL Magic](https://github.com/catherinedevlin/ipython-sql)
- [JupySQL](https://ploomber.io/blog/jupysql/)

### Community Examples
- [KevsterAmp's LazyVim Config](https://github.com/KevsterAmp/Lazyvim-config.nvim)
- [Quarto Neovim Kickstarter](https://github.com/jmbuhr/quarto-nvim-kickstarter)
