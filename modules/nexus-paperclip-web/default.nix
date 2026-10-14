{ config, lib, ... }:

let
  cfg = config.myConfig.modules.nexus-paperclip-web;
  address = "10.77.0.1";
  port = 3100;
  upstreamHost = "127.0.0.1:${builtins.toString port}";
  upstream = "http://${upstreamHost}";
  ph = config.sops.placeholder;
in
{
  options.myConfig.modules.nexus-paperclip-web = {
    enable = lib.mkEnableOption "Paperclip web UI on wg-nexus (WireGuard keys are the login), proxied to the loopback Paperclip server";
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops file holding paperclip-web-password and paperclip-web-password-hash, the crypt hash for basic auth user tom";
    };
  };
  config = lib.mkIf cfg.enable {
    sops = {
      secrets.paperclip-web-password-hash.sopsFile = cfg.sopsFile;
      templates."paperclip-web.htpasswd" = {
        owner = config.services.nginx.user;
        mode = "0400";
        reloadUnits = [ "nginx.service" ];
        content = ''
          tom:${ph.paperclip-web-password-hash}
        '';
      };
    };
    services.nginx = {
      enable = true;
      virtualHosts.paperclip-wg = {
        listen = [
          {
            addr = address;
            inherit port;
          }
        ];
        locations."/" = {
          proxyPass = upstream;
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_set_header Host ${upstreamHost};
            proxy_set_header X-Forwarded-Host "";
            proxy_set_header Origin http://${upstreamHost};
            proxy_set_header Authorization "";
            proxy_read_timeout 1h;
            proxy_buffering off;
            client_max_body_size 50M;
            sub_filter '<head>' '<head><script>if(window.crypto&&!crypto.randomUUID){crypto.randomUUID=function(){var b=crypto.getRandomValues(new Uint8Array(16)),h=[];b[6]=b[6]&15|64;b[8]=b[8]&63|128;for(var i=0;i<16;i++){h.push((b[i]+256).toString(16).slice(1));if(i==3||i==5||i==7||i==9)h.push("-")}return h.join("")}}</script>';
            sub_filter_once on;
          '';
        };
      };
    };
    networking.firewall.interfaces.wg-nexus.allowedTCPPorts = [ port ];
  };
}
