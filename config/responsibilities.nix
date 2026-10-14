{
  config,
  lib,
  options,
  ...
}:
let
  catalog = config.myConfig.responsibilities;
  inherit (catalog) responsibilities software;
  closure =
    roots:
    map (entry: entry.key) (
      builtins.genericClosure {
        startSet = map (key: { inherit key; }) roots;
        operator = entry: map (key: { inherit key; }) (responsibilities.${entry.key}.dependsOn or [ ]);
      }
    );
  responsible = closure (catalog.hosts.${config.networking.hostName} or [ ]);
  obligations = lib.concatMap (
    name: map (program: { inherit name program; }) responsibilities.${name}.requiresSoftware
  ) responsible;
  realized =
    program:
    software.${program}.module != null
    && builtins.hasAttr software.${program}.module options.myConfig.modules;
  enabled = program: realized program && config.myConfig.modules.${software.${program}.module}.enable;
  strings = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };
  nullableString = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };
in
{
  options.myConfig.responsibilities = lib.mkOption {
    default = builtins.fromJSON (builtins.readFile ./responsibilities.json);
    description = "Host responsibilities, software realization, capabilities and system domains";
    type = lib.types.submodule {
      options = {
        hosts = lib.mkOption { type = lib.types.attrsOf (lib.types.listOf lib.types.str); };
        responsibilities = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                dependsOn = strings;
                requiresCapabilities = strings;
                requiresSoftware = strings;
                domain = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.enum [
                      "boot"
                      "environment"
                    ]
                  );
                  default = null;
                };
                criticality = nullableString;
                lifecycle = nullableString;
              };
            }
          );
        };
        software = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                module = nullableString;
                capabilities = strings;
              };
            }
          );
        };
      };
    };
  };
  config.assertions = [
    {
      assertion = lib.all (obligation: realized obligation.program) obligations;
      message = "Every software requirement on ${config.networking.hostName} must name a realizing module.";
    }
    {
      assertion = lib.all (
        obligation:
        responsibilities.${obligation.name}.domain != "environment" || !enabled obligation.program
      ) obligations;
      message = "Environment software on ${config.networking.hostName} must remain outside the boot system modules.";
    }
    {
      assertion = lib.all (
        name:
        responsibilities.${name}.domain != "boot"
        || lib.all (dependency: responsibilities.${dependency}.domain != "environment") (
          closure responsibilities.${name}.dependsOn
        )
      ) responsible;
      message = "Boot responsibilities on ${config.networking.hostName} cannot depend on environment responsibilities.";
    }
    {
      assertion = lib.all (
        obligation:
        realized obligation.program
        && responsibilities.${obligation.name}.domain != null
        && responsibilities.${obligation.name}.criticality != null
        && (
          responsibilities.${obligation.name}.domain != "boot"
          || responsibilities.${obligation.name}.lifecycle != null
        )
      ) obligations;
      message = "Software responsibilities on ${config.networking.hostName} require realization, domain and criticality; boot responsibilities also require lifecycle.";
    }
    {
      assertion = lib.all (
        name:
        lib.all (
          capability:
          lib.any (
            program: builtins.elem capability software.${program}.capabilities
          ) responsibilities.${name}.requiresSoftware
        ) responsibilities.${name}.requiresCapabilities
      ) responsible;
      message = "Every required capability on ${config.networking.hostName} must be provided by the responsibility's required software.";
    }
    {
      assertion = lib.all (
        obligation:
        responsibilities.${obligation.name}.domain != "boot"
        || (
          responsibilities.${obligation.name}.lifecycle == "long-lived-system-service"
          && enabled obligation.program
        )
      ) obligations;
      message = "Boot software on ${config.networking.hostName} must be enabled and declared as a long-lived system service.";
    }
  ];
}
