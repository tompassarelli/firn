{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.mini-serve.enable {
    "systemd" = {
      "services" = {
        "mini-serve" = {
          "after" = [ "network.target" ];
          "description" = "Minimal localhost web server";
          "serviceConfig" = {
            "DynamicUser" = true;
            "ExecStart" = (((("" + builtins.toString pkgs.darkhttpd) + "/bin/darkhttpd ") + builtins.toString (pkgs.writeTextDir "index.html" "<!DOCTYPE html><html><body style=\"background:#2b3339;margin:0\"></body></html>\n\n")) + " --port 39847 --addr 127.0.0.1");
            "Restart" = "always";
          };
          "wantedBy" = [ "multi-user.target" ];
        };
      };
    };
  };
  options."myConfig"."modules"."mini-serve"."enable" = lib.mkEnableOption "Enable mini-serve localhost background page";
}
