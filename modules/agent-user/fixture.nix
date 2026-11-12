{
  myConfig.modules.system.stateVersion = "25.05";
  myConfig.modules.users.username = "operator";
  users.users.operator = {
    isNormalUser = true;
    uid = 1000;
  };
  myConfig.modules.agent-user.enable = true;
  myConfig.modules.agent-claude-managed.enable = true;
  myConfig.modules.agent-brokers = {
    enable = true;
    operatorUid = 1000;
    threadsSocket = "/run/user/1000/north-threads.sock";
  };
  myConfig.modules.agent-cache-seed = {
    enable = true;
    sources = {
      "/home/operator/.cargo/registry" = "/home/agent/.cargo/registry";
      "/home/operator/.cache/sccache" = "/home/agent/.cache/sccache";
      "/home/operator/.cache/cargo-target" = "/home/agent/.cache/cargo-target";
    };
  };
  myConfig.modules.agent-runtime-link = {
    enable = true;
    target = "/var/lib/agent-runtime/runtimes/fixture";
  };
}
