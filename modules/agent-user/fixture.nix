{
  myConfig = {
    modules = {
      system.stateVersion = "25.05";
      users.username = "operator";
      agent-user.enable = true;
      agent-claude-managed.enable = true;
      agent-brokers = {
        enable = true;
        operatorUid = 1000;
        threadsSocket = "/run/user/1000/north-threads.sock";
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
