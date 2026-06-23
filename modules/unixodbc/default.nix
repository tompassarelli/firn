{ config, lib, pkgs, ... }:

let
  msodbcsql18 = pkgs.unstable.unixodbcDrivers.msodbcsql18;
in
{
  options.myConfig.modules.unixodbc.enable = lib.mkEnableOption "unixODBC with MSSQL driver";
  config = lib.mkIf config.myConfig.modules.unixodbc.enable {
    environment.systemPackages = [ pkgs.unixodbc msodbcsql18 ];
    environment.variables = {
      ODBCSYSINI = "/etc";
      ODBCINI = "/etc/odbc.ini";
    };
    environment.etc = {
      "odbcinst.ini".text = ''
        [ODBC Driver 18 for SQL Server]
        Description = Microsoft ODBC Driver 18 for SQL Server
        Driver = ${msodbcsql18}/lib/libmsodbcsql-18.1.so.1.1

      '';
      "odbc.ini".text = ''
        [msa_data]
        Driver = ODBC Driver 18 for SQL Server
        Server = localhost
        Database = msa_data
        TrustServerCertificate = Yes

      '';
    };
  };
}
