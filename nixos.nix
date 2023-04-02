{ inputs'nvidia-patch, config, pkgs, lib, ... }: with lib; let
  cfg = config.hardware.nvidia;
  inherit (config.boot) kernelPackages;
in {
  options = with types; {
    hardware.nvidia.patch = {
      enable = mkEnableOption "nvidia-patch" // {
        default = cfg.patch.softEnable && (if !cfg.patch.package.meta.broken
          then true
          else warn "nvidia-patch out of date" false);
      };
      softEnable = mkEnableOption "nvidia-patch (if possible)";
      nvidiaPackage = mkOption {
        type = package;
        defaultText = literalExpression "config.boot.kernelPackages.nvidiaPackages.stable";
        default = kernelPackages.nvidiaPackages.stable;
      };
      package = mkOption {
        type = package;
        defaultText = literalExpression "config.boot.kernelPackages.nvidia-patch";
        default = kernelPackages.nvidia-patch or (kernelPackages.callPackage ./derivation.nix {
          nvidia_x11 = cfg.patch.nvidiaPackage;
          nvidia-patch-src = inputs'nvidia-patch.lib.src;
          nvidia-patch-drivers = inputs'nvidia-patch.lib.driversFor {
            inherit (pkgs) hostPlatform;
          };
        });
      };
    };
  };

  config = {
    hardware.nvidia.package = mkIf cfg.patch.enable cfg.patch.package;
    _module.args.inputs'nvidia-patch = mkOptionDefault (import ./default.nix { inherit pkgs; });
  };
}
