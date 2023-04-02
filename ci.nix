{ config, pkgs, lib, ... }: with pkgs; with lib; let
  nvidia-patch = import ./. { pkgs = null; };
  inherit (nvidia-patch) checks packages;
  build = runCommand {
    inherit (packages.nvidia-patch) name;
    inherit (packages) nvidia-patch;
    allowSubstitutes = true;
  } ''
    mkdir -p $out/nix-support
  '';
in {
  config = {
    name = "nvidia-patch";
    system = "x86_64-linux";
    ci.gh-actions.enable = true;
    channels = {
      nixpkgs.args.config.allowUnfree = true;
    };
    tasks = {
      build.inputs = singleton build;
      version-supported.inputs = singleton checks.supported;
    };
  };
}
