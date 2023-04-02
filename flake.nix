{
  description = "removes restriction imposed by Nvidia to consumer-grade GPUs";
  inputs = {
    flakelib.url = "github:flakelib/fl";
    nixpkgs = { };
    nvidia-patch-src = {
      url = "github:keylase/nvidia-patch";
      flake = false;
    };
  };
  outputs = { self, flakelib, nixpkgs, nvidia-patch-src, ... }@inputs: let
    nixlib = nixpkgs.lib;
    mapLinuxPackages = packages: {
      inherit (packages) nvidia-patch nvidia-patches nvidiaPackages;
    };
  in flakelib {
    inherit inputs;
    systems = [ "x86_64-linux" ];
    packages = {
      nvidia-patch = { outputs'legacyPackages'linuxPackages }: outputs'legacyPackages'linuxPackages.nvidia-patch;
      default = { nvidia-patch }: nvidia-patch;
    };
    legacyPackages = { callPackageSet }: callPackageSet {
      pkgs = { system, config ? { }, overlays ? [ ] }: import nixpkgs {
        inherit system;
        config = config // {
          allowUnfree = true;
        };
        overlays = overlays ++ [
          self.overlays.default
        ];
      };
      linuxKernelPackages = { outputs'legacyPackages'pkgs }: nixlib.mapAttrs (_: mapLinuxPackages) outputs'legacyPackages'pkgs.linuxKernel.packages;
      linuxPackages = { outputs'legacyPackages'pkgs }: mapLinuxPackages outputs'legacyPackages'pkgs.linuxPackages;
      linuxPackages_latest = { outputs'legacyPackages'pkgs }: mapLinuxPackages outputs'legacyPackages'pkgs.linuxPackages_latest;
      nvidia-patch-drivers = { outputs'legacyPackages'pkgs }: outputs'legacyPackages'pkgs.nvidia-patch-drivers;
    } { };
    checks = {
      supported = { runCommand, nvidia-patch }: runCommand "${nvidia-patch.version}-support" {
        meta.broken = !nvidia-patch.meta.available;
        nvidia_x11 = builtins.unsafeDiscardStringContext nvidia-patch.outPath;
      } ''
        touch $out
      '';
    };
    lib = with nixlib; let
      manifestPath = nvidia-patch-src + "/drivers.json";
      manifest = importJSON (manifestPath);
    in {
      src = nvidia-patch-src;
      manifest = manifest // {
        outPath = manifestPath;
        data = manifest;
      };
      drivers = let
        mapLinux = arch: { version, nvenc_patch ? false, nvfbc_patch ? false, driver_url ? null, ... }@args: nameValuePair version (args // {
          ${if driver_url != null then "fetch_driver" else null} = { fetchurl ? builtins.fetchurl, ... }@args: fetchurl ({
            url = driver_url;
          } // nixlib.removeAttrs args [ "fetchurl" ]);
          inherit arch nvenc_patch nvfbc_patch;
        });
        mapWindows = arch: { version, variant ? "", product ? "GeForce", patch32_url ? null, patch64_url ? null, driver_url ? null, ... }@args: let
          variantName = {
            "DCH" = "";
            "DCH (Hotfix)" = "";
            "Studio Driver" = "Studio";
          }.${toString variant} or variant;
          name = version
            + optionalString (product != "GeForce") "-${product}"
            + optionalString (variantName != "") "-${variantName}"
          ;
        in nameValuePair name (args // {
          inherit arch;
          ${if patch32_url != null then "patch32" else null} = nvidia-patch-src + "/win/${patch32_url}";
          ${if patch64_url != null then "patch64" else null} = nvidia-patch-src + "/win/${patch64_url}";
          ${if driver_url != null then "driver" else null} = builtins.fetchurl driver_url;
        });
      in {
        linux = mapAttrs (arch: { drivers, ... }: listToAttrs (map (mapLinux arch) drivers)) manifest.linux;
        win = mapAttrs (arch: { drivers, ... }: listToAttrs (map (mapWindows arch) drivers)) manifest.win;
      };
      latestVersion = let
        latest = mapAttrs (arch: drivers: last (sort (a: b: versionAtLeast a.version b.version) (attrValues drivers)));
      in mapAttrs (platform: latest) {
        inherit (self.lib.drivers) linux win;
      };
      driversFor = { hostPlatform }: let
        driversOs = if hostPlatform.isLinux then "linux"
          else if hostPlatform.isWindows then "win"
          else throw "unsupported nvidia-patch os ${hostPlatform.system}";
      in self.lib.drivers.${driversOs}.${hostPlatform.linuxArch};
    };
    overlays = {
      nvidia-patch = final: prev: {
        nvidia-patch-drivers = let
          driversOs = if final.hostPlatform.isLinux then "linux"
            else if final.hostPlatform.isWindows then "win"
            else throw "unsupported nvidia-patch os ${final.hostPlatform.system}";
        in self.lib.driversFor { inherit (final) hostPlatform; };
        linuxKernel = prev.linuxKernel // {
          packagesFor = kernel: (prev.linuxKernel.packagesFor kernel).extend (kfinal: kprev: let
            callPackage = args: kfinal.callPackage ./derivation.nix ({
              inherit nvidia-patch-src;
              inherit (final) nvidia-patch-drivers;
            } // args);
          in {
            nvidia-patch = callPackage { };
            nvidia-patches = nixlib.mapAttrs (_: nvidia_x11: nvidia_x11.patch) (nixlib.filterAttrs (_: nixlib.isDerivation) kfinal.nvidiaPackages);
            nvidiaPackages = kprev.nvidiaPackages.extend (nfinal: nprev: nixlib.mapAttrs (name: nvidia_x11: let
              drv = nvidia_x11 // {
                patch = callPackage {
                  inherit nvidia_x11;
                };
              };
            in if nixlib.isDerivation nvidia_x11 then drv else nvidia_x11) nprev);
          });
        };
      };
      default = self.overlays.nvidia-patch;
    };
    nixosModules = {
      nvidia-patch = { lib, ... }: {
        imports = [ ./nixos.nix ];
        config = {
          _module.args.inputs'nvidia-patch = lib.mkDefault self;
        };
      };
      default = self.nixosModules.nvidia-patch;
    };
    config = rec {
      name = "nvidia-patch";
    };
  };
}
