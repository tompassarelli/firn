{
  description = "firn — composable NixOS and nix-darwin modules with evaluation checks before rebuild";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix.url = "github:danth/stylix/release-26.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
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
    elephant.url = "github:abenz1267/elephant/0348d14ed9238309d2ae984f5010877470b06a73";
    nur.url = "github:nix-community/NUR";
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
  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-master,
      home-manager,
      nix-darwin,
      stylix,
      sops-nix,
      kanata-git,
      glide,
      ...
    }:
    let
      firnModules = ./modules;
      moduleMetadata = import ./config/module-metadata.nix {
        inherit (nixpkgs) lib;
        modulesPath = firnModules;
      };
      moduleInputNames = nixpkgs.lib.unique (
        nixpkgs.lib.concatMap (metadata: builtins.attrNames metadata.flakeInputs) (
          builtins.attrValues moduleMetadata
        )
      );
      moduleInputs = nixpkgs.lib.filterAttrs (name: _: builtins.elem name moduleInputNames) inputs;
      darwinModuleNames = builtins.fromJSON (builtins.readFile ./config/darwin-modules.json);
      environmentPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      whiterabbitEnvironmentApps = [
        environmentPkgs.blender
        environmentPkgs.obsidian
      ];
      validateDomainDependency =
        dependency:
        if ((dependency.dependentDomain == "boot") && (dependency.requiredDomain == "environment")) then
          builtins.throw "boot responsibilities cannot require the environment domain"
        else
          dependency;
      mkWhiterabbitEnvironment =
        includeExperimentPackage:
        home-manager.lib.homeManagerConfiguration {
          pkgs = environmentPkgs;
          modules = [
            ({ pkgs, ... }: {
              home = {
                username = "tom";
                homeDirectory = "/home/tom";
                stateVersion = "25.05";
                packages = whiterabbitEnvironmentApps ++ (if includeExperimentPackage then [ pkgs.hello ] else [ ]);
              };
            })
          ];
        };
      mkWhiterabbitWorld = includeExperimentPackage: {
        boot = self.lib.mkSystem {
          hostname = "whiterabbit";
          hostConfig = ./hosts/whiterabbit/configuration.nix;
          hardwareConfig = ./hardware-configuration.nix;
        };
        environment = mkWhiterabbitEnvironment includeExperimentPackage;
      };
      whiterabbitEnvironment = mkWhiterabbitEnvironment false;
      baselineWorld = mkWhiterabbitWorld false;
      toggledWorld = mkWhiterabbitWorld true;
      rejectedDependency = builtins.tryEval (validateDomainDependency {
        dependentDomain = "boot";
        requiredDomain = "environment";
      });
    in
    {
      lib.mkSystem =
        {
          hostname,
          hostConfig,
          hardwareConfig,
          system ? "x86_64-linux",
          extraModules ? [ ],
          extraOverlays ? [ ],
          extraSpecialArgs ? { },
          ...
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inputs = moduleInputs;
            flakeRoot = self;
          }
          // extraSpecialArgs;
          modules = [
            hardwareConfig
            stylix.nixosModules.stylix
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            hostConfig
            ./config/responsibilities.nix
            (
              if builtins.pathExists (builtins.dirOf hostConfig + "/tags.json") then
                import ./config/tags.nix { tagsFile = builtins.dirOf hostConfig + "/tags.json"; }
              else
                { }
            )
            ({ config, pkgs, ... }: {
              assertions = map (name: {
                assertion =
                  builtins.hasAttr name inputs
                  &&
                    builtins.length (
                      nixpkgs.lib.unique (
                        nixpkgs.lib.concatMap (
                          metadata:
                          nixpkgs.lib.optional (builtins.hasAttr name metadata.flakeInputs) metadata.flakeInputs.${name}
                        ) (builtins.attrValues moduleMetadata)
                      )
                    ) == 1;
                message = "Module flake input ${name} must be declared and have exactly one source URL.";
              }) moduleInputNames;
              networking.hostName = hostname;
              system.configurationRevision =
                if builtins.hasAttr "rev" self then
                  self.rev
                else if builtins.hasAttr "dirtyRev" self then
                  self.dirtyRev
                else
                  null;
              sops.age.keyFile = nixpkgs.lib.mkIf (
                !config.myConfig.modules.sops-host-key.enable
              ) "/var/lib/sops-nix/key.txt";
              environment.sessionVariables.SOPS_AGE_KEY_FILE = nixpkgs.lib.mkIf (
                !config.myConfig.modules.sops-host-key.enable
              ) "/var/lib/sops-nix/key.txt";
              systemd.tmpfiles.rules = nixpkgs.lib.mkIf (!config.myConfig.modules.sops-host-key.enable) [
                "z /var/lib/sops-nix/key.txt 0400 ${config.myConfig.modules.users.username} users -"
              ];
              environment.systemPackages = with pkgs; [
                sops
                age
              ];
              imports =
                let
                  moduleDirs = builtins.attrNames (
                    nixpkgs.lib.filterAttrs (_n: v: (v == "directory")) (builtins.readDir ./modules)
                  );
                in
                builtins.map (m: firnModules + "/${m}") moduleDirs;
              home-manager = {
                backupFileExtension = "backup";
                extraSpecialArgs = {
                  inputs = moduleInputs;
                }
                // extraSpecialArgs;
                users.${config.myConfig.modules.users.username} = {
                  home.stateVersion = config.myConfig.modules.system.stateVersion;
                  nixpkgs.config.allowUnfree = true;
                };
              };
            })
            {
              nixpkgs.overlays = [
                (final: _prev: {
                  unstable = import nixpkgs-unstable {
                    inherit system;
                    config.allowUnfree = true;
                  };
                  master = import nixpkgs-master {
                    inherit system;
                    config.allowUnfree = true;
                  };
                  kanata-git = final.unstable.kanata.overrideAttrs (_old: {
                    src = kanata-git;
                    version = "git";
                    cargoDeps = final.unstable.rustPlatform.importCargoLock { lockFile = "${kanata-git}/Cargo.lock"; };
                    doCheck = false;
                    doInstallCheck = false;
                  });
                  glide = final.unstable.rustPlatform.buildRustPackage {
                    pname = "glide";
                    version = "git";
                    src = glide;
                    cargoLock.lockFile = "${glide}/Cargo.lock";
                  };
                  nyxt4 =
                    let
                      nyxt-tarball = final.fetchurl {
                        url = "https://github.com/atlas-engineer/nyxt/releases/download/4.0.0/Linux-Nyxt-x86_64.tar.gz";
                        hash = "sha256-v+x6K5svLA3L+IjEdTjmJEf3hvgwhwrvqAcelpY1ScQ=";
                      };
                      nyxt-appimage = final.runCommand "nyxt.AppImage" { } ''
                        tar xzf ${nyxt-tarball} -O > $out
                        chmod +x $out

                      '';
                      nyxt-extracted = final.appimageTools.extractType2 {
                        pname = "nyxt";
                        version = "4.0.0";
                        src = nyxt-appimage;
                      };
                      cl-electron-extracted = final.appimageTools.extractType2 {
                        pname = "cl-electron-server";
                        version = "4.0.0";
                        src = "${nyxt-extracted}/usr/bin/cl-electron-server";
                      };
                      nyxt-unwrapped = final.runCommand "nyxt-unwrapped-4.0.0" { } ''
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

                      '';
                    in
                    final.buildFHSEnv {
                      pname = "nyxt";
                      version = "4.0.0";
                      targetPkgs =
                        p: with p; [
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
                    };
                })
              ]
              ++ extraOverlays;
            }
          ]
          ++ extraModules;
        };
      lib.mkDarwinSystem =
        {
          hostname,
          hostConfig,
          system ? "aarch64-darwin",
          extraModules ? [ ],
          extraOverlays ? [ ],
          extraSpecialArgs ? { },
          ...
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inputs = moduleInputs;
            flakeRoot = self;
          }
          // extraSpecialArgs;
          modules = [
            home-manager.darwinModules.home-manager
            hostConfig
            (
              if builtins.pathExists (builtins.dirOf hostConfig + "/tags.json") then
                import ./config/tags.nix { tagsFile = builtins.dirOf hostConfig + "/tags.json"; }
              else
                { }
            )
            ({ config, lib, ... }: {
              imports = builtins.map (m: firnModules + "/${m}") darwinModuleNames;
              options.myConfig.modules.users = {
                username = lib.mkOption {
                  type = lib.types.str;
                  default = "you";
                  description = "Primary system username";
                };
                email = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Primary git/commit email";
                };
                fullName = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Git author / display name";
                };
              };
              config = {
                networking.hostName = hostname;
                system.stateVersion = "6";
                nixpkgs.config.allowUnfree = true;
                users.users."${config.myConfig.modules.users.username}".home =
                  "/Users/${config.myConfig.modules.users.username}";
                home-manager = {
                  backupFileExtension = "backup";
                  extraSpecialArgs = {
                    inputs = moduleInputs;
                  }
                  // extraSpecialArgs;
                  users."${config.myConfig.modules.users.username}" = {
                    home = {
                      username = config.myConfig.modules.users.username;
                      homeDirectory = "/Users/${config.myConfig.modules.users.username}";
                      stateVersion = "25.11";
                    };
                    nixpkgs.config.allowUnfree = true;
                  };
                };
              };
            })
            {
              nixpkgs.overlays = [
                (_final: _prev: {
                  unstable = import nixpkgs-unstable {
                    inherit system;
                    config.allowUnfree = true;
                  };
                  master = import nixpkgs-master {
                    inherit system;
                    config.allowUnfree = true;
                  };
                })
              ]
              ++ extraOverlays;
            }
          ]
          ++ extraModules;
        };
      modules = firnModules;
      checks.x86_64-linux = {
        host-whiterabbit = self.nixosConfigurations.whiterabbit.config.system.build.toplevel;
        nix-syntax =
          let
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            source = nixpkgs.lib.fileset.toSource {
              root = ./.;
              fileset = nixpkgs.lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
            };
          in
          pkgs.runCommand "firn-nix-syntax"
            {
              nativeBuildInputs = [
                pkgs.nix
                pkgs.findutils
              ];
            }
            ''
              export NIX_STATE_DIR="$TMPDIR/nix-state"
              find ${source} -type f -name '*.nix' -print0 | while IFS= read -r -d ''' file; do
                nix-instantiate --store dummy:// --parse "$file" >/dev/null
              done
              touch $out
            '';
      };
      homeConfigurations = {
        "tom@whiterabbit" = whiterabbitEnvironment;
      };
      packages.x86_64-linux.whiterabbit-environment = environmentPkgs.buildEnv {
        name = "whiterabbit-environment";
        paths = whiterabbitEnvironmentApps;
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
        bootIdentityIndependent =
          baselineWorld.boot.config.system.build.toplevel.drvPath
          == toggledWorld.boot.config.system.build.toplevel.drvPath;
        environmentIdentityChanged =
          baselineWorld.environment.activationPackage.drvPath
          != toggledWorld.environment.activationPackage.drvPath;
        bootEnvironmentDependencyRejected = !rejectedDependency.success;
      };
      nixosConfigurations = {
        whiterabbit = self.lib.mkSystem {
          hostname = "whiterabbit";
          hostConfig = ./hosts/whiterabbit/configuration.nix;
          hardwareConfig = ./hardware-configuration.nix;
        };
      };
      templates.default = {
        description = "firn starter configuration";
        path = ./template;
      };
      devShells.x86_64-linux.default =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          packages = [
            pkgs.pre-commit
            pkgs.gitleaks
          ];
          shellHook = ''
            pre-commit install --allow-missing-config 2>/dev/null

          '';
        };
    };
}
