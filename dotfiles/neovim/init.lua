-- Apply stylix colors first
require('stylix-colors').setup()

-- Enable folding
vim.opt.foldmethod = "expr"

-- #region folding function
function GetRegionFold(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("#region") then
    return ">1"
  elseif line:match("#endregion") then
    return "<1"
  end
  return "="
end

vim.opt.foldexpr = "v:lua.GetRegionFold(v:lnum)"

-- Auto-apply for file types that use #region / #endregion
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "nix", "css", "javascript", "typescript" },
  callback = function()
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.GetRegionFold(v:lnum)"
  end,
})

-- Set leader key to space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Basic settings
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- System clipboard integration
vim.opt.clipboard = "unnamedplus"

-- LSP setup for Rust
vim.api.nvim_create_autocmd("FileType", {
  pattern = "rust",
  callback = function()
    vim.lsp.start({
      name = "rust-analyzer",
      cmd = {"rust-analyzer"},
      root_dir = vim.fs.dirname(vim.fs.find({"Cargo.toml", ".git"}, {upward = true})[1]),
    })
  end,
})

-- LSP setup for Nix: typenix for types, nil for nixfmt formatting
vim.api.nvim_create_autocmd("FileType", {
  pattern = "nix",
  callback = function(ev)
    local root_dir = vim.fs.root(ev.buf, {"flake.nix", ".git"})
    vim.lsp.start({
      name = "typenix",
      cmd = {"typenix", "--lsp", "--stdio"},
      root_dir = root_dir,
    })
    vim.lsp.start({
      name = "nil",
      cmd = {"nil"},
      root_dir = root_dir,
      settings = { ["nil"] = { formatting = { command = {"nixfmt"} } } },
    })
  end,
})

-- Common leader key mappings
vim.keymap.set("n", "<leader>w", ":w<CR>", { desc = "Save file" })
vim.keymap.set("n", "<leader>q", ":q<CR>", { desc = "Quit" })
vim.keymap.set("n", "<leader>wq", ":wq<CR>", { desc = "Save and quit" })
vim.keymap.set("n", "<leader>h", ":nohlsearch<CR>", { desc = "Clear highlights" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostics" })
vim.keymap.set("n", "<leader>n", ":bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<leader>p", ":bprev<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "<leader>x", ":bd<CR>", { desc = "Close buffer" })

-- LSP keybindings
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", {}),
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>f", function()
      vim.lsp.buf.format {
        async = true,
        filter = function(client) return client.name ~= "typenix" end,
      }
    end, opts)
    vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, opts)
  end,
})
