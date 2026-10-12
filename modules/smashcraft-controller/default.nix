{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.smashcraft-controller.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = hm: {
          "systemd" = {
            "user" = {
              "services" = {
                "wc3-controller" = {
                  "Install" = {
                    "WantedBy" = [ "niri.service" ];
                  };
                  "Service" = {
                    "ExecStart" = (((("" + ((hm.config).home).homeDirectory) + "/.local/share/wc3-controller/bin/wc3-controller --service --plugin ") + ((hm.config).home).homeDirectory) + "/.local/share/smashcraft-build-inputs/controller/wc3-journal");
                    "Restart" = "always";
                    "RestartSec" = "5";
                  };
                  "Unit" = {
                    "After" = [ "graphical-session.target" ];
                    "ConditionPathExists" = (("" + ((hm.config).home).homeDirectory) + "/.local/share/wc3-controller/bin/wc3-controller");
                    "Description" = "wc3-controller service";
                    "PartOf" = [ "graphical-session.target" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."smashcraft-controller"."enable" = lib.mkEnableOption "wc3-controller service: Tom's Xbox controller in Warcraft III, with Smashcraft's plug-in";
}
