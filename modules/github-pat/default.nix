{ config, lib, pkgs, ... }:

((cfg: ((username: ((applyPath: ((workPath: ((selector: ((ghWrapper: {
  options.myConfig.modules.github-pat.enable = lib.mkEnableOption "per-repository GitHub PATs from sops for git and gh";
  options.myConfig.modules.github-pat.sopsFile = lib.mkOption {
    type = lib.types.path;
    description = "sops file holding the nexus-apply and nexus-work tokens";
  };
  options.myConfig.modules.github-pat.applyRepos = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "tompassarelli/firn" "tompassarelli/north" "tompassarelli/south" ];
    description = "lower-case OWNER/REPO names that use the read-only nexus-apply token";
  };
  options.myConfig.modules.github-pat.nixAccessToken = lib.mkEnableOption "the read-only nexus-apply token as nix's github.com access token, so root nix can fetch private flakes";
  config = lib.mkIf cfg.enable {
    sops.secrets.nexus-apply = {
      sopsFile = cfg.sopsFile;
      owner = username;
      mode = "0400";
    };
    sops.templates.nix-access-tokens = lib.mkIf cfg.nixAccessToken {
      content = ''
        access-tokens = github.com=${config.sops.placeholder.nexus-apply}
      '';
      owner = "root";
      mode = "0400";
    };
    nix.extraOptions = lib.mkIf cfg.nixAccessToken ''
      !include ${config.sops.templates.nix-access-tokens.path}
    '';
    sops.secrets.nexus-work = {
      sopsFile = cfg.sopsFile;
      owner = username;
      mode = "0400";
    };
    environment.systemPackages = [ selector ghWrapper ];
    home-manager.users.${username} = ({ config, ... }: {
      programs.git.settings.credential = {
        "https://github.com" = {
          helper = "!${selector}/bin/github-pat credential";
          useHttpPath = true;
        };
      };
    });
  };
}) (pkgs.writeShellApplication {
    name = "gh";
    runtimeInputs = [ selector ];
    text = ''
      if [ -z "$(printenv GH_TOKEN)" ]; then
        repo=$(github-pat repo "$@")
        [ -z "$(printenv GITHUB_PAT_TRACE)" ] || echo "github-pat: $(github-pat key "$repo") for $repo" >&2
        GH_TOKEN=$(github-pat token "$repo")
        export GH_TOKEN
      fi
      exec ${pkgs.gh}/bin/gh "$@"
    '';
  }))) (pkgs.writeShellApplication {
    name = "github-pat";
    runtimeInputs = [ pkgs.coreutils pkgs.git pkgs.gnugrep pkgs.gnused ];
    text = ''
      usage() { echo 'usage: github-pat key|token OWNER/REPO | credential get | repo [ARGS...]' >&2; exit 2; }
      key_for() {
        repo=$(printf %s "$1" | tr '[:upper:]' '[:lower:]')
        repo=$(basename "$(dirname "$repo")")/$(basename "$repo" .git)
        case "$repo" in
          ${lib.concatStringsSep "|" cfg.applyRepos}) echo nexus-apply ;;
          *) echo nexus-work ;;
        esac
      }
      token_for() {
        case "$(key_for "$1")" in
          nexus-apply) cat ${applyPath} ;;
          *) cat ${workPath} ;;
        esac
      }
      repo_of() {
        prev='''
        for arg in "$@"; do
          case "$prev" in -R|--repo) echo "$arg"; return ;; esac
          case "$arg" in --repo=*) echo "$arg" | cut -d= -f2-; return ;; esac
          prev=$arg
        done
        for arg in "$@"; do
          found=$(printf %s "$arg" | grep -oE '(repos/|github\.com[/:])[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -n1 | sed -E 's#^(repos/|github\.com[/:])##') || true
          [ -n "$found" ] && { echo "$found"; return; }
        done
        git remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[/:]##' || true
      }
      [ $# -ge 1 ] || usage
      cmd=$1; shift
      case "$cmd" in
        key) [ $# -eq 1 ] || usage; key_for "$1" ;;
        token) [ $# -eq 1 ] || usage; token_for "$1" ;;
        repo) repo_of "$@" ;;
        credential)
          [ "$#" -ge 1 ] && [ "$1" = get ] || exit 0
          host='''; path='''
          while IFS='=' read -r k v; do
            [ -n "$k" ] || break
            case "$k" in host) host=$v ;; path) path=$v ;; esac
          done
          [ "$host" = github.com ] && [ -n "$path" ] || exit 0
          [ -z "$(printenv GITHUB_PAT_TRACE)" ] || echo "github-pat: $(key_for "$path") for $path" >&2
          printf 'username=x-access-token\npassword=%s\n' "$(token_for "$path")" ;;
        *) usage ;;
      esac
    '';
  }))) config.sops.secrets.nexus-work.path)) config.sops.secrets.nexus-apply.path)) config.myConfig.modules.users.username)) config.myConfig.modules.github-pat)
