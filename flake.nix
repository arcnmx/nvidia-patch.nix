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
  in flakelib {
    inherit inputs;
    systems = [ "x86_64-linux" ];
    packages = {
      nvidia-patch = { outputs'legacyPackages'pkgs }: outputs'legacyPackages'pkgs.linuxPackages.nvidia-patch;
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
      linuxKernelPackages = { outputs'legacyPackages'pkgs }: nixlib.mapAttrs (_: packages: {
        inherit (packages) nvidia-patch;
      }) outputs'legacyPackages'pkgs.linuxKernel.packages;
      nvidia-patch-drivers = { outputs'legacyPackages'pkgs }: outputs'legacyPackages'pkgs.nvidia-patch-drivers;
    } { };
    lib = with nixlib; let
      manifestPath = nvidia-patch-src + "/drivers.json";
      manifest = importJSON (manifestPath);
    in {
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
    };
    overlays = {
      nvidia-patch = final: prev: {
        nvidia-patch-drivers = let
          driversOs = if final.hostPlatform.isLinux then "linux"
            else if final.hostPlatform.isWindows then "win"
            else throw "unsupported nvidia-patch os ${final.hostPlatform.system}";
        in self.lib.drivers.${driversOs}.${final.hostPlatform.linuxArch};
        linuxKernel = prev.linuxKernel // {
          packagesFor = kernel: (prev.linuxKernel.packagesFor kernel).extend (kfinal: kprev: {
            nvidia-patch = kfinal.callPackage ./derivation.nix {
              inherit nvidia-patch-src;
              inherit (final) nvidia-patch-drivers;
              nvidia_x11 = kprev.nvidiaPackages.latest;
            };
            nvidiaPackages = nixlib.mapAttrs (_: nvidia_x11: kfinal.nvidia-patch.override {
              inherit nvidia_x11;
            }) kprev.nvidiaPackages;
          });
        };
      };
      default = self.overlays.nvidia-patch;
    };
    config = rec {
      name = "nvidia-patch";
    };
  };
}
