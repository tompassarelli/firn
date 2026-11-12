{ pkgs, ... }:
{
  myConfig = {
    modules = {
      system.stateVersion = "25.05";
      users.username = "operator";
      agent-user = {
        enable = true;
        gid = 1500;
      };
      agent-claude-managed.enable = true;
      agent-brokers = {
        enable = true;
        package = pkgs.coreutils;
        policy = "/etc/north-broker/policy.toml";
      };
      agent-cache-seed = {
        enable = true;
        sources = {
          "/home/operator/.cargo/registry" = "/home/agent/.cargo/registry";
          "/home/operator/.cache/sccache" = "/home/agent/.cache/sccache";
          "/home/operator/.cache/cargo-target" = "/home/agent/.cache/cargo-target";
        };
      };
      agent-runtime-link = {
        enable = true;
        target = "/var/lib/agent-runtime/runtimes/fixture";
      };
    };
  };
  users.users.operator = {
    isNormalUser = true;
    uid = 1000;
  };
}
