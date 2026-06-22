{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code CLI configuration";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    environment.systemPackages = [ pkgs.master.claude-code ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/settings.json";
        ".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
        ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/skills";
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/CLAUDE.md";
        ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/hooks";

        # ~/code root routing instruction — was untracked-on-disk; now reproducible.
        "code/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/CLAUDE.md";

        # caveman defaultMode — was ad-hoc in ~/.config. Static config we own; the plugin reads it.
        # (Runtime mode marker ~/.claude/.caveman-active stays unmanaged — the plugin rewrites it on /caveman switch.)
        ".config/caveman/config.json".text = builtins.toJSON { defaultMode = "lite"; };
      };

      # caveman plugin INSTALL: enablement is declared in settings.json, but the on-disk install
      # (~/.claude/plugins/cache) is runtime state. Best-effort idempotent install — never fails the
      # rebuild (|| true) and timeout-bounded so a network stall can't hang activation. Fresh machine
      # self-heals on first activation with network; otherwise finish with a manual `claude plugin install`.
      home.activation.installCaveman = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e "${config.home.homeDirectory}/.claude/plugins/cache/caveman" ]; then
          run timeout 90 ${pkgs.master.claude-code}/bin/claude plugin marketplace add JuliusBrussee/caveman || true
          run timeout 90 ${pkgs.master.claude-code}/bin/claude plugin install caveman@caveman || true
        fi
      '';
    });
  };
}
