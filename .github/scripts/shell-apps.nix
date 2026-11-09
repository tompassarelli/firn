{ root, module }:
let
  flake = builtins.getFlake "path:${root}";
  host = flake.nixosConfigurations.whiterabbit;
  inherit (host) lib;
  path = /. + "${root}/${module}";
  declared =
    (import path (
      host._module.specialArgs
      // host._module.args
      // {
        inherit lib;
        inherit (host) config options;
      }
    )).options or { };
  placeholder =
    type:
    {
      str = "firn-check";
      nonEmptyStr = "firn-check";
      path = "/firn-check";
      int = 1;
      port = 1;
      bool = false;
      listOf = [ (placeholder type.nestedTypes.elemType) ];
      nonEmptyListOf = [ (placeholder type.nestedTypes.elemType) ];
      attrsOf = { };
      nullOr = null;
    }
    .${type.name} or null;
  settings =
    prefix: options:
    lib.concatMapAttrs (
      name: option:
      if lib.isOption option then
        if name == "enable" then
          { ${name} = true; }
        else if option ? default || placeholder option.type == null then
          { }
        else
          { ${name} = placeholder option.type; }
      else if lib.isAttrs option then
        let
          nested = settings (prefix ++ [ name ]) option;
        in
        lib.optionalAttrs (nested != { }) { ${name} = nested; }
      else
        { }
    ) options;
  optionPaths =
    prefix: options:
    lib.concatLists (
      lib.mapAttrsToList (
        name: option:
        if lib.isOption option then
          [ (prefix ++ [ name ]) ]
        else if lib.isAttrs option then
          optionPaths (prefix ++ [ name ]) option
        else
          [ ]
      ) options
    );
  imported = builtins.any (p: lib.hasAttrByPath p host.options) (optionPaths [ ] declared);
  enabled = host.extendModules {
    modules = lib.optional (!imported) path ++ [ (settings [ ] declared) ];
  };
  args =
    enabled._module.specialArgs
    // enabled._module.args
    // {
      inherit lib;
      inherit (enabled) config options;
    };
  contribution = (import path args).config or { };
  isPackageSet = value: value ? callPackage || value ? __functor;
  collect =
    depth: value:
    let
      tried = builtins.tryEval value;
      v = tried.value;
    in
    if !tried.success || depth > 16 then
      [ ]
    else if lib.isDerivation v then
      let
        drv = builtins.tryEval v.drvPath;
      in
      lib.optional drv.success drv.value
    else if builtins.isString v then
      builtins.attrNames (builtins.getContext v)
    else if builtins.isList v then
      lib.concatMap (collect (depth + 1)) v
    else if builtins.isFunction v then
      collect (depth + 1) (v args)
    else if builtins.isAttrs v && (v._type or null) == "if" then
      lib.optionals (builtins.tryEval v.condition).value (collect (depth + 1) v.content)
    else if builtins.isAttrs v && (v._type or null) == "merge" then
      collect (depth + 1) v.contents
    else if builtins.isAttrs v && (v._type or null) == "override" then
      collect (depth + 1) v.content
    else if builtins.isAttrs v && !isPackageSet v then
      lib.concatMap (collect (depth + 1)) (builtins.attrValues v)
    else
      [ ];
in
lib.unique (collect 0 contribution)
