{ pkgs, ... }:

((buildLayeredImage: buildLayeredImage {
  name = "claude-sandbox";
  tag = "latest";
  contents = with pkgs; [
    bashInteractive
    coreutils
    gnused
    gnugrep
    findutils
    gawk
    less
    which
    gnutar
    gzip
    xz
    git
    gh
    openssh
    nix
    claude-code
    nodejs
    python3
    ripgrep
    fd
    curl
    jq
  ];
  extraCommands = ''
    mkdir -p home/dev/.claude
    mkdir -p home/dev/.config/nix
    mkdir -p work
    mkdir -p tmp
    chmod 1777 tmp
    mkdir -p nix/var/nix/{profiles,gcroots,db}
    mkdir -p etc
    echo "dev:x:1000:1000::/home/dev:/bin/bash" > etc/passwd
    echo "dev:x:1000:" > etc/group
    # Enable flakes and nix-command in container
    echo "experimental-features = nix-command flakes" > home/dev/.config/nix/nix.conf
    # Starter flake for declarative package management
    cp ${./devshell-flake.nix} home/dev/flake.nix
    chmod 644 home/dev/flake.nix
    # Instructions for Claude Code
    cp ${./CLAUDE.md} work/CLAUDE.md
    chmod 644 work/CLAUDE.md

  '';
  config = {
    Cmd = [ "/bin/bash" ];
    WorkingDir = "/work";
    User = "dev";
    Env = [
      "HOME=/home/dev"
      "USER=dev"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "NIX_CONF_DIR=/home/dev/.config/nix"
    ];
  };
}) pkgs.dockerTools.buildLayeredImage)
