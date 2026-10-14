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
  unrealized = builtins.filter (obligation: !realized obligation.program) obligations;
  coupledEnvironment = builtins.filter (
    obligation:
    responsibilities.${obligation.name}.domain == "environment" && enabled obligation.program
  ) obligations;
  coupledBoot = builtins.filter (
    name:
    responsibilities.${name}.domain == "boot"
    && lib.any (dependency: responsibilities.${dependency}.domain == "environment") (
      closure responsibilities.${name}.dependsOn
    )
  ) responsible;
  incomplete = builtins.filter (
    obligation:
    !(
      realized obligation.program
      && responsibilities.${obligation.name}.domain != null
      && responsibilities.${obligation.name}.criticality != null
      && (
        responsibilities.${obligation.name}.domain != "boot"
        || responsibilities.${obligation.name}.lifecycle != null
      )
    )
  ) obligations;
  missingCapabilities = lib.concatMap (
    name:
    map (capability: "${name}/${capability}") (
      builtins.filter (
        capability:
        !(lib.any (
          program: builtins.elem capability software.${program}.capabilities
        ) responsibilities.${name}.requiresSoftware)
      ) responsibilities.${name}.requiresCapabilities
    )
  ) responsible;
  invalidBoot = builtins.filter (
    obligation:
    responsibilities.${obligation.name}.domain == "boot"
    && !(
      responsibilities.${obligation.name}.lifecycle == "long-lived-system-service"
      && enabled obligation.program
    )
  ) obligations;
  obligationNames =
    entries: lib.concatStringsSep ", " (map (entry: "${entry.name}/${entry.program}") entries);
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
      assertion = unrealized == [ ];
      message = "Responsibilities/software ${obligationNames unrealized} on ${config.networking.hostName} must name a realizing module.";
    }
    {
      assertion = coupledEnvironment == [ ];
      message = "Environment responsibilities/software ${obligationNames coupledEnvironment} on ${config.networking.hostName} must remain outside the boot system modules.";
    }
    {
      assertion = coupledBoot == [ ];
      message = "Boot responsibilities ${lib.concatStringsSep ", " coupledBoot} on ${config.networking.hostName} cannot depend on environment responsibilities.";
    }
    {
      assertion = incomplete == [ ];
      message = "Responsibilities/software ${obligationNames incomplete} on ${config.networking.hostName} require realization, domain and criticality; boot responsibilities also require lifecycle.";
    }
    {
      assertion = missingCapabilities == [ ];
      message = "Responsibilities/capabilities ${lib.concatStringsSep ", " missingCapabilities} on ${config.networking.hostName} must be provided by the responsibility's required software.";
    }
    {
      assertion = invalidBoot == [ ];
      message = "Boot responsibilities/software ${obligationNames invalidBoot} on ${config.networking.hostName} must be enabled and declared as a long-lived system service.";
    }
  ];
}
