{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.dictation;
  model = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin";
    hash = "sha256-v9/0iU3Ldrv2R9ViY+oqlmRUI/FmkXb0hEob+OR4rTA=";
  };
  dictate = pkgs.writeShellApplication {
    name = "dictate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.pipewire
      pkgs.wtype
      pkgs.whisper-cpp
    ];
    text = ''
      export DICTATION_MODEL=${model}
      export DICTATION_KEY=${cfg.key}
      ${builtins.readFile ./dictate}
    '';
  };
  listener = pkgs.writeShellScript "dictation-listener" ''
    exec ${pkgs.coreutils}/bin/stdbuf -oL ${pkgs.libinput}/bin/libinput debug-events --show-keycodes \
      | ${dictate}/bin/dictate listen
  '';
in
{
  options.myConfig.modules.dictation = {
    enable = lib.mkEnableOption "Hold-to-talk dictation: record the mic while a key is held, transcribe with local whisper.cpp on release, type the text into the focused window";
    key = lib.mkOption {
      type = lib.types.str;
      default = "KEY_F20";
      description = "evdev key name to hold while speaking; kanata maps the Menu key to it (dotfiles/kanata/kanata.kbd), and neither Niri nor Claude Code's voice mode (hold Space) binds it";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ dictate ];
    home-manager.users.${config.myConfig.modules.users.username}.systemd.user.services.dictation = {
      Install.WantedBy = [ "niri.service" ];
      Service = {
        ExecStart = "${listener}";
        Restart = "on-failure";
      };
      Unit = {
        After = [ "graphical-session.target" ];
        Description = "Hold-to-talk dictation key listener";
        PartOf = [ "graphical-session.target" ];
        Requisite = [ "graphical-session.target" ];
      };
    };
  };
}
