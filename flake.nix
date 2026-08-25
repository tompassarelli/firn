{
  description = "firn — typed authoring layer for NixOS/nix-darwin; catches config typos and type errors at the source line, before rebuild";
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-26.05";
    };
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs-master = {
      url = "github:nixos/nixpkgs/master";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix/release-26.05";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kanata-git = {
      url = "github:jtroo/kanata";
      flake = false;
    };
    glide = {
      url = "github:tompassarelli/glide";
      flake = false;
    };
    elephant = {
      url = "github:abenz1267/elephant/0348d14ed9238309d2ae984f5010877470b06a73";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    quickshell = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
    };
    walker = {
      inputs.elephant.follows = "elephant";
      url = "github:abenz1267/walker";
    };
    zen-browser = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:0xc000022070/zen-browser-flake";
    };
  };
  outputs = ({ self, nixpkgs, nixpkgs-unstable, nixpkgs-master, home-manager, nix-darwin, stylix, sops-nix, kanata-git, glide, elephant, nur, quickshell, walker, zen-browser, ... }: ((firnModules: ((darwinModuleNames: ((environmentPkgs: ((validateDomainDependency: ((mkWhiterabbitEnvironment: ((mkWhiterabbitWorld: ((baselineWorld: ((toggledWorld: ((rejectedDependency: {
    lib.mkSystem = ({ hostname, hostConfig, hardwareConfig, system ? "x86_64-linux", extraModules ? [ ], extraOverlays ? [ ], extraSpecialArgs ? { }, ... }: nixpkgs.lib.nixosSystem {
      system = system;
      specialArgs = ({
        inputs = {
          elephant = elephant;
          nur = nur;
          quickshell = quickshell;
          walker = walker;
          zen-browser = zen-browser;
        };
        flakeRoot = self;
      } // extraSpecialArgs);
      modules = ([
        hardwareConfig
        stylix.nixosModules.stylix
        home-manager.nixosModules.home-manager
        sops-nix.nixosModules.sops
        hostConfig
        ({ config, pkgs, ... }: {
          networking.hostName = hostname;
          sops.age.keyFile = "/var/lib/sops-nix/key.txt";
          environment.sessionVariables.SOPS_AGE_KEY_FILE = "/var/lib/sops-nix/key.txt";
          systemd.tmpfiles.rules = [
            "z /var/lib/sops-nix/key.txt 0400 ${config.myConfig.modules.users.username} users -"
          ];
          environment.systemPackages = with pkgs; [ sops age ];
          imports = ((moduleDirs: ((builtins.map (m: "${firnModules}/${m}") moduleDirs))) (builtins.attrNames (nixpkgs.lib.filterAttrs (n: v: (v == "directory")) (builtins.readDir ./modules))));
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = ({
            inputs = {
              elephant = elephant;
              nur = nur;
              quickshell = quickshell;
              walker = walker;
              zen-browser = zen-browser;
            };
          } // extraSpecialArgs);
          home-manager.users."${config.myConfig.modules.users.username}" = {
            home.stateVersion = config.myConfig.modules.system.stateVersion;
            nixpkgs.config.allowUnfree = true;
          };
        })
        {
          nixpkgs.overlays = ([
            (final: prev: {
              unstable = import nixpkgs-unstable {
                system = system;
                config.allowUnfree = true;
              };
              master = import nixpkgs-master {
                system = system;
                config.allowUnfree = true;
              };
              kanata-git = final.unstable.kanata.overrideAttrs (old: {
                src = kanata-git;
                version = "git";
                cargoDeps = final.unstable.rustPlatform.importCargoLock {
                  lockFile = "${kanata-git}/Cargo.lock";
                };
                doCheck = false;
                doInstallCheck = false;
              });
              glide = final.unstable.rustPlatform.buildRustPackage {
                pname = "glide";
                version = "git";
                src = glide;
                cargoLock.lockFile = "${glide}/Cargo.lock";
              };
              nyxt4 = ((nyxt-tarball: ((nyxt-appimage: ((nyxt-extracted: ((cl-electron-extracted: ((nyxt-unwrapped: final.buildFHSEnv {
                pname = "nyxt";
                version = "4.0.0";
                targetPkgs = p: with p; [
                  nyxt-unwrapped
                  glib
                  gobject-introspection
                  gdk-pixbuf
                  cairo
                  pango
                  gtk3
                  webkitgtk_4_1
                  openssl
                  libfixposix
                  enchant2
                  sqlite
                  glib-networking
                  gsettings-desktop-schemas
                  gst_all_1.gstreamer
                  gst_all_1.gst-plugins-base
                  gst_all_1.gst-plugins-good
                  xdg-utils
                  wl-clipboard
                  fuse
                  nss
                  nspr
                  atk
                  cups
                  dbus
                  expat
                  libdrm
                  mesa
                  libgbm
                  alsa-lib
                  at-spi2-core
                  libxkbcommon
                  pciutils
                  xorg.libX11
                  xorg.libXcomposite
                  xorg.libXdamage
                  xorg.libXext
                  xorg.libXfixes
                  xorg.libXrandr
                  xorg.libxcb
                  xorg.libXcursor
                  xorg.libXi
                  xorg.libXrender
                  xorg.libXtst
                  xorg.libXScrnSaver
                  systemd
                  libGL
                  libglvnd
                  egl-wayland
                ];
                extraBwrapArgs = [ "--bind ${nyxt-unwrapped}/app /app" ];
                runScript = final.writeShellScript "nyxt-wrapper" ''
                  export APPDIR=/app/Nyxt
                  export PATH="/app/Nyxt/_build/cl-electron:$PATH"
                  export ELECTRON_OZONE_PLATFORM_HINT=auto
                  exec /app/Nyxt/nyxt "$@"

                '';
                extraInstallCommands = ''
                  mkdir -p $out/share
                  ln -s ${nyxt-unwrapped}/share/applications $out/share/applications
                  ln -s ${nyxt-unwrapped}/share/icons $out/share/icons

                '';
              }) (final.runCommand "nyxt-unwrapped-4.0.0" { } ''
                  mkdir -p $out/app/Nyxt/_build/cl-electron $out/share/applications $out/share/icons/hicolor/256x256/apps

                  # Nyxt binary and libs
                  cp ${nyxt-extracted}/usr/bin/nyxt $out/app/Nyxt/
                  cp -r ${nyxt-extracted}/usr/lib/* $out/app/Nyxt/ 2>/dev/null || true

                  # cl-electron (full Electron distribution)
                  cp -r ${cl-electron-extracted}/* $out/app/Nyxt/_build/cl-electron/

                  # Desktop integration
                  cp ${nyxt-extracted}/nyxt.desktop $out/share/applications/ 2>/dev/null || true
                  cp ${nyxt-extracted}/nyxt.png $out/share/icons/hicolor/256x256/apps/ 2>/dev/null || true
                  sed -i "s|Exec=.*|Exec=nyxt %u|" $out/share/applications/nyxt.desktop 2>/dev/null || true

                ''))) (final.appimageTools.extractType2 {
                  pname = "cl-electron-server";
                  version = "4.0.0";
                  src = "${nyxt-extracted}/usr/bin/cl-electron-server";
                }))) (final.appimageTools.extractType2 {
                  pname = "nyxt";
                  version = "4.0.0";
                  src = nyxt-appimage;
                }))) (final.runCommand "nyxt.AppImage" { } ''
                  tar xzf ${nyxt-tarball} -O > $out
                  chmod +x $out

                ''))) (final.fetchurl {
                  url = "https://github.com/atlas-engineer/nyxt/releases/download/4.0.0/Linux-Nyxt-x86_64.tar.gz";
                  hash = "sha256-v+x6K5svLA3L+IjEdTjmJEf3hvgwhwrvqAcelpY1ScQ=";
                }));
            })
          ] ++ extraOverlays);
        }
      ] ++ extraModules);
    });
    lib.mkDarwinSystem = ({ hostname, hostConfig, system ? "aarch64-darwin", extraModules ? [ ], extraOverlays ? [ ], extraSpecialArgs ? { }, ... }: nix-darwin.lib.darwinSystem {
      system = system;
      specialArgs = ({
        inputs = {
          elephant = elephant;
          nur = nur;
          quickshell = quickshell;
          walker = walker;
          zen-browser = zen-browser;
        };
        flakeRoot = self;
      } // extraSpecialArgs);
      modules = ([
        home-manager.darwinModules.home-manager
        hostConfig
        ({ config, lib, pkgs, ... }: {
          imports = ((builtins.map (m: "${firnModules}/${m}") darwinModuleNames));
          options.myConfig.modules.users.username = lib.mkOption {
            type = lib.types.str;
            default = "you";
            description = "Primary system username";
          };
          options.myConfig.modules.users.email = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Primary git/commit email";
          };
          options.myConfig.modules.users.fullName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Git author / display name";
          };
          config = {
            networking.hostName = hostname;
            system.stateVersion = 6;
            nixpkgs.config.allowUnfree = true;
            users.users."${config.myConfig.modules.users.username}".home = "/Users/${config.myConfig.modules.users.username}";
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = ({
              inputs = {
                elephant = elephant;
                nur = nur;
                quickshell = quickshell;
                walker = walker;
                zen-browser = zen-browser;
              };
            } // extraSpecialArgs);
            home-manager.users."${config.myConfig.modules.users.username}" = {
              home.username = config.myConfig.modules.users.username;
              home.homeDirectory = "/Users/${config.myConfig.modules.users.username}";
              home.stateVersion = "25.11";
              nixpkgs.config.allowUnfree = true;
            };
          };
        })
        {
          nixpkgs.overlays = ([
            (final: prev: {
              unstable = import nixpkgs-unstable {
                system = system;
                config.allowUnfree = true;
              };
              master = import nixpkgs-master {
                system = system;
                config.allowUnfree = true;
              };
            })
          ] ++ extraOverlays);
        }
      ] ++ extraModules);
    });
    modules = firnModules;
    homeConfigurations = {
      "tom@whiterabbit" = mkWhiterabbitEnvironment false;
    };
    domainIndependence = {
      baseline = {
        bootDrvPath = baselineWorld.boot.config.system.build.toplevel.drvPath;
        environmentDrvPath = baselineWorld.environment.activationPackage.drvPath;
      };
      environmentToggle = {
        bootDrvPath = toggledWorld.boot.config.system.build.toplevel.drvPath;
        environmentDrvPath = toggledWorld.environment.activationPackage.drvPath;
      };
      bootIdentityIndependent = (baselineWorld.boot.config.system.build.toplevel.drvPath == toggledWorld.boot.config.system.build.toplevel.drvPath);
      environmentIdentityChanged = (baselineWorld.environment.activationPackage.drvPath != toggledWorld.environment.activationPackage.drvPath);
      bootEnvironmentDependencyRejected = !rejectedDependency.success;
    };
    nixosConfigurations = {
      whiterabbit = self.lib.mkSystem {
        hostname = "whiterabbit";
        hostConfig = ./hosts/whiterabbit/configuration.nix;
        hardwareConfig = ./hardware-configuration.nix;
      };
      thinkpad-x1e = self.lib.mkSystem {
        hostname = "thinkpad-x1e";
        hostConfig = ./hosts/thinkpad-x1e/configuration.nix;
        hardwareConfig = ./hardware-configuration.nix;
      };
    };
    darwinConfigurations = {
      ashashi = self.lib.mkDarwinSystem {
        hostname = "ashashi";
        hostConfig = ./hosts/ashashi/configuration.nix;
      };
    };
    templates.default = {
      description = "firn starter configuration";
      path = ./template;
    };
    devShells.x86_64-linux.default = ((pkgs: pkgs.mkShell {
      packages = [ pkgs.pre-commit pkgs.gitleaks ];
      shellHook = ''
        pre-commit install --allow-missing-config 2>/dev/null

      '';
    }) nixpkgs.legacyPackages.x86_64-linux);
  }) (builtins.tryEval (validateDomainDependency {
      dependentDomain = "boot";
      requiredDomain = "environment";
    })))) (mkWhiterabbitWorld true))) (mkWhiterabbitWorld false))) (includeExperimentPackage: {
      boot = self.lib.mkSystem {
        hostname = "whiterabbit";
        hostConfig = ./hosts/whiterabbit/configuration.nix;
        hardwareConfig = ./hardware-configuration.nix;
      };
      environment = mkWhiterabbitEnvironment includeExperimentPackage;
    }))) (includeExperimentPackage: home-manager.lib.homeManagerConfiguration {
      pkgs = environmentPkgs;
      modules = [
        ({ pkgs, ... }: {
          home.username = "tom";
          home.homeDirectory = "/home/tom";
          home.stateVersion = "25.05";
          home.packages = if includeExperimentPackage then [ pkgs.hello ] else [ ];
        })
      ];
    }))) (dependency: if ((dependency.dependentDomain == "boot") && (dependency.requiredDomain == "environment")) then builtins.throw "boot responsibilities cannot require the environment domain" else dependency))) nixpkgs.legacyPackages.x86_64-linux)) (builtins.fromJSON (builtins.readFile ./config/darwin-modules.json)))) ./modules));
}
