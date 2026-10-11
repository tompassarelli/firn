{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.postgresql.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.postgresql_18 ];
    };
    "services" = {
      "postgresql" = {
        "authentication" = pkgs.lib.mkOverride 10 "# TYPE  DATABASE        USER            ADDRESS                 METHOD\nlocal   all             all                                     trust\nhost    all             all             127.0.0.1/32            trust\nhost    all             all             ::1/128                 trust\n\n";
        "enable" = true;
        "ensureDatabases" = [ "postgres" ];
        "ensureUsers" = [
          {
            "ensureClauses" = {
              "superuser" = true;
            };
            "name" = "postgres";
          }
        ];
        "package" = pkgs.unstable.postgresql_18;
      };
    };
  };
  options."myConfig"."modules"."postgresql"."enable" = lib.mkEnableOption "PostgreSQL database server for local development";
}
