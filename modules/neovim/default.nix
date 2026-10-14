{ config, lib, ... }:
let
  cfg = config.myConfig.modules.neovim;
in
{
  options.myConfig.modules.neovim.enable = lib.mkEnableOption "Neovim text editor";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      xdg.configFile = {
        "nvim/init.lua".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/neovim/init.lua";
        "nvim/lua/stylix-colors.lua".text = ''
          local M = {}

          -- Base16 color palette
          M.palette = {
            base00 = "#${hm.config.lib.stylix.colors.base00}",
            base01 = "#${hm.config.lib.stylix.colors.base01}",
            base02 = "#${hm.config.lib.stylix.colors.base02}",
            base03 = "#${hm.config.lib.stylix.colors.base03}",
            base04 = "#${hm.config.lib.stylix.colors.base04}",
            base05 = "#${hm.config.lib.stylix.colors.base05}",
            base06 = "#${hm.config.lib.stylix.colors.base06}",
            base07 = "#${hm.config.lib.stylix.colors.base07}",
            base08 = "#${hm.config.lib.stylix.colors.base08}",
            base09 = "#${hm.config.lib.stylix.colors.base09}",
            base0A = "#${hm.config.lib.stylix.colors.base0A}",
            base0B = "#${hm.config.lib.stylix.colors.base0B}",
            base0C = "#${hm.config.lib.stylix.colors.base0C}",
            base0D = "#${hm.config.lib.stylix.colors.base0D}",
            base0E = "#${hm.config.lib.stylix.colors.base0E}",
            base0F = "#${hm.config.lib.stylix.colors.base0F}"
          }

          -- Stylix colorscheme setup function (adapted from stylix neovim.nix)
          M.setup = function()
            -- Try to use mini.base16 if available, fallback to manual highlights
            local ok, mini_base16 = pcall(require, 'mini.base16')
            if ok then
              mini_base16.setup({ palette = M.palette })
            else
              -- Manual highlight setup as fallback
              vim.cmd.highlight({ "Normal", "guifg=" .. M.palette.base05, "guibg=" .. M.palette.base00 })
              vim.cmd.highlight({ "Comment", "guifg=" .. M.palette.base03 })
              vim.cmd.highlight({ "String", "guifg=" .. M.palette.base0B })
              vim.cmd.highlight({ "Keyword", "guifg=" .. M.palette.base0E })
              vim.cmd.highlight({ "Function", "guifg=" .. M.palette.base0D })
              vim.cmd.highlight({ "Type", "guifg=" .. M.palette.base0A })
              vim.cmd.highlight({ "Constant", "guifg=" .. M.palette.base09 })
              vim.cmd.highlight({ "Error", "guifg=" .. M.palette.base08 })
              -- Add transparency if desired
              -- vim.cmd.highlight({ "Normal", "guibg=NONE", "ctermbg=NONE" })
            end
          end

          return M

        '';
      };
    };
    programs.neovim = {
      defaultEditor = true;
      enable = true;
    };
  };
}
