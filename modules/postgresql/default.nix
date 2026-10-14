{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.postgresql;
in
{
  options.myConfig.modules.postgresql.enable =
    lib.mkEnableOption "PostgreSQL database server for local development";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.unstable.postgresql_18 ];
    services.postgresql = {
      authentication = pkgs.lib.mkOverride 10 ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     trust
        host    all             all             127.0.0.1/32            trust
        host    all             all             ::1/128                 trust

      '';
      enable = true;
      ensureDatabases = [ "postgres" ];
      ensureUsers = [
        {
          ensureClauses.superuser = true;
          name = "postgres";
        }
      ];
      package = pkgs.unstable.postgresql_18;
    };
  };
}
