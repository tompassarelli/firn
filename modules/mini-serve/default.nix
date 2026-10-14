{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.mini-serve;
in
{
  options.myConfig.modules.mini-serve.enable =
    lib.mkEnableOption "Enable mini-serve localhost background page";
  config = lib.mkIf cfg.enable {
    systemd.services.mini-serve = {
      after = [ "network.target" ];
      description = "Minimal localhost web server";
      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${pkgs.darkhttpd}/bin/darkhttpd ${pkgs.writeTextDir "index.html" ''
          <!DOCTYPE html><html><body style="background:#2b3339;margin:0"></body></html>

        ''} --port 39847 --addr 127.0.0.1";
        Restart = "always";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
