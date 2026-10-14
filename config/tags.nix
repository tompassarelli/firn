{ tagsFile }:
{ config, lib, ... }:
let
  cfg = host;
  host = builtins.fromJSON (builtins.readFile tagsFile);
  platforms = builtins.fromJSON (builtins.readFile ./platforms.json);
  modules = import ./module-metadata.nix {
    inherit lib;
    modulesPath = ../modules;
  };
  moduleNames = builtins.attrNames modules;
  knownTags = lib.unique (
    lib.concatMap (name: modules.${name}.tags ++ modules.${name}.optIn) moduleNames
  );
  supported =
    name:
    (platforms.${cfg.platform}.all or false)
    || builtins.elem cfg.platform (modules.${name}.supports or [ ]);
  defaultsFor = tag: builtins.filter (name: builtins.elem tag modules.${name}.tags) moduleNames;
  selectedDefaults =
    tag:
    builtins.filter (name: supported name && !(builtins.elem name (cfg.drops.${tag} or [ ]))) (
      defaultsFor tag
    );
  selectedFor =
    tag:
    selectedDefaults tag
    ++ builtins.filter (
      name: builtins.hasAttr name modules && supported name && builtins.elem tag modules.${name}.optIn
    ) (cfg.adds.${tag} or [ ]);
  active = builtins.filter (name: !(builtins.elem name (cfg.disables ++ cfg.turnsOff))) (
    lib.unique (lib.concatMap selectedFor cfg.enables)
  );
  overrideValues = lib.concatMap (
    tag:
    lib.concatMap (
      name:
      lib.mapAttrsToList (path: value: { inherit path value; }) (modules.${name}.overrides.${tag} or { })
    ) (builtins.filter (name: builtins.elem name active) (selectedDefaults tag))
  ) cfg.enables;
  overrideConfigs = map (
    entry: lib.setAttrByPath (lib.splitString "." entry.path) (lib.mkDefault entry.value)
  ) overrideValues;
  overridesByPath = lib.groupBy (entry: entry.path) overrideValues;
  listOption = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };
  editsOption = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
  };
in
{
  options.myConfig.tags = lib.mkOption {
    type = lib.types.submodule {
      options = {
        platform = lib.mkOption { type = lib.types.enum (builtins.attrNames platforms); };
        enables = listOption;
        disables = listOption;
        turnsOn = listOption;
        turnsOff = listOption;
        adds = editsOption;
        drops = editsOption;
      };
    };
    readOnly = true;
    description = "Host tag composition and direct module selections";
  };
  config = lib.mkMerge (
    [
      {
        myConfig.tags = host;
        assertions = [
          {
            assertion = builtins.deepSeq config.myConfig.tags true;
            message = "Host tag composition must satisfy its declared option types.";
          }
          {
            assertion = lib.all (tag: builtins.elem tag knownTags) cfg.enables;
            message = "Host ${config.networking.hostName} enables undeclared tags: ${
              lib.concatStringsSep ", " (builtins.filter (tag: !(builtins.elem tag knownTags)) cfg.enables)
            }.";
          }
          {
            assertion = lib.all (name: builtins.hasAttr name modules) (
              cfg.disables ++ cfg.turnsOn ++ cfg.turnsOff
            );
            message = "Host ${config.networking.hostName} selects or disables unknown modules: ${
              lib.concatStringsSep ", " (
                builtins.filter (name: !(builtins.hasAttr name modules)) (
                  cfg.disables ++ cfg.turnsOn ++ cfg.turnsOff
                )
              )
            }.";
          }
        ]
        ++ lib.mapAttrsToList (path: entries: {
          assertion = builtins.length (lib.unique (map (entry: builtins.toJSON entry.value) entries)) == 1;
          message = "Host ${config.networking.hostName} receives conflicting tag values for ${path}.";
        }) overridesByPath
        ++ lib.concatLists (
          lib.mapAttrsToList (
            tag: names:
            map (name: {
              assertion = builtins.hasAttr name modules && builtins.elem tag modules.${name}.optIn;
              message = "Host ${config.networking.hostName} adds ${name} to ${tag}, but that module does not allow this opt-in tag.";
            }) names
            ++ map (name: {
              assertion = builtins.hasAttr name modules && supported name;
              message = "Host ${config.networking.hostName} adds ${name} to ${tag}, but it does not support ${cfg.platform}.";
            }) names
          ) cfg.adds
        );
        warnings = lib.concatMap (
          tag:
          map (
            name:
            "Host ${config.networking.hostName} drops ${name} from ${tag}, but it is not a default member."
          ) (builtins.filter (name: !(builtins.elem name (defaultsFor tag))) (cfg.drops.${tag} or [ ]))
        ) cfg.enables;
      }
      {
        myConfig.modules = lib.genAttrs active (_: {
          enable = lib.mkDefault true;
        });
      }
      {
        myConfig.modules = lib.genAttrs cfg.turnsOn (_: {
          enable = true;
        });
      }
      {
        myConfig.modules = lib.genAttrs cfg.turnsOff (_: {
          enable = false;
        });
      }
    ]
    ++ overrideConfigs
  );
}
