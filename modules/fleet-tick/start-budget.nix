rec {
  runtimeDeployDeadlineSeconds = 120;
  probeSeconds = 14;
  swapSeconds = runtimeDeployDeadlineSeconds + probeSeconds;
  startSeconds = swapSeconds + 16;
}
