{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.ironbar.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.ironbar ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = __clause_argument_0: {
          "systemd" = {
            "user" = {
              "services" = {
                "ironbar" = {
                  "Install" = {
                    "WantedBy" = [ "niri.service" ];
                  };
                  "Service" = {
                    "ExecStart" = (("" + builtins.toString pkgs.unstable.ironbar) + "/bin/ironbar");
                    "Restart" = "on-failure";
                  };
                  "Unit" = {
                    "After" = [ "graphical-session.target" ];
                    "Description" = "Customizable GTK4 status bar for Wayland";
                    "PartOf" = [ "graphical-session.target" ];
                    "Requisite" = [ "graphical-session.target" ];
                  };
                };
                "ironbar-overview" = {
                  "Install" = {
                    "WantedBy" = [ "niri.service" ];
                  };
                  "Service" = {
                    "ExecStart" = "%h/.config/ironbar/overview-ironbar.py";
                    "Restart" = "on-failure";
                  };
                  "Unit" = {
                    "After" = [ "ironbar.service" ];
                    "Description" = "Ironbar overview listener script";
                    "PartOf" = [ "graphical-session.target" ];
                    "Requires" = [ "ironbar.service" ];
                  };
                };
              };
            };
          };
          "xdg" = {
            "configFile" = {
              "ironbar/battery.sh" = {
                "source" = (((__clause_argument_0.config).lib).file).mkOutOfStoreSymlink (("" + ((__clause_argument_0.config).home).homeDirectory) + "/code/nixos-config/dotfiles/ironbar/battery.sh");
              };
              "ironbar/config.toml" = {
                "source" = (((__clause_argument_0.config).lib).file).mkOutOfStoreSymlink (("" + ((__clause_argument_0.config).home).homeDirectory) + "/code/nixos-config/dotfiles/ironbar/config.toml");
              };
              "ironbar/overview-ironbar.py" = {
                "source" = (((__clause_argument_0.config).lib).file).mkOutOfStoreSymlink (("" + ((__clause_argument_0.config).home).homeDirectory) + "/code/nixos-config/dotfiles/ironbar/overview-ironbar.py");
              };
              "ironbar/style.css" = {
                "source" = (((__clause_argument_0.config).lib).file).mkOutOfStoreSymlink (("" + ((__clause_argument_0.config).home).homeDirectory) + "/code/nixos-config/dotfiles/ironbar/style.css");
              };
              "ironbar/stylix.css" = {
                "text" = (((((((((((((((((((((((((((((((((((((((("@define-color base00 #" + ((((__clause_argument_0.config).lib).stylix).colors).base00) + ";\n@define-color base01 #") + ((((__clause_argument_0.config).lib).stylix).colors).base01) + ";\n@define-color base02 #") + ((((__clause_argument_0.config).lib).stylix).colors).base02) + ";\n@define-color base03 #") + ((((__clause_argument_0.config).lib).stylix).colors).base03) + ";\n@define-color base04 #") + ((((__clause_argument_0.config).lib).stylix).colors).base04) + ";\n@define-color base05 #") + ((((__clause_argument_0.config).lib).stylix).colors).base05) + ";\n@define-color base06 #") + ((((__clause_argument_0.config).lib).stylix).colors).base06) + ";\n@define-color base07 #") + ((((__clause_argument_0.config).lib).stylix).colors).base07) + ";\n@define-color base08 #") + ((((__clause_argument_0.config).lib).stylix).colors).base08) + ";\n@define-color base09 #") + ((((__clause_argument_0.config).lib).stylix).colors).base09) + ";\n@define-color base0A #") + ((((__clause_argument_0.config).lib).stylix).colors).base0A) + ";\n@define-color base0B #") + ((((__clause_argument_0.config).lib).stylix).colors).base0B) + ";\n@define-color base0C #") + ((((__clause_argument_0.config).lib).stylix).colors).base0C) + ";\n@define-color base0D #") + ((((__clause_argument_0.config).lib).stylix).colors).base0D) + ";\n@define-color base0E #") + ((((__clause_argument_0.config).lib).stylix).colors).base0E) + ";\n@define-color base0F #") + ((((__clause_argument_0.config).lib).stylix).colors).base0F) + ";\n\n* {\n  font-family: \"") + ((((__clause_argument_0.config).stylix).fonts).monospace).name) + "\";\n  font-size: ") + builtins.toString ((((__clause_argument_0.config).stylix).fonts).sizes).desktop) + "pt;\n}\n\n.background {\n  background: alpha(@base00, ") + builtins.toString (((__clause_argument_0.config).stylix).opacity).desktop) + ");\n  color: @base05;\n}\n\ntooltip {\n  background: alpha(@base00, ") + builtins.toString (((__clause_argument_0.config).stylix).opacity).desktop) + ");\n  color: @base05;\n  border-color: @base0D;\n}\n\n");
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."ironbar"."enable" = lib.mkEnableOption "Ironbar status bar for Wayland";
}
