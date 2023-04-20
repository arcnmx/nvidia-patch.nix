{ pkgs, config, lib, env, ... }: with lib; let
  tasks.check.inputs = pkgs.ci.command {
    name = "flake-check";
    displayName = "nix flake check";
    cache.enable = false;
    allowSubstitutes = false;
    depends = [
      config.tasks.update.drv
    ];
    command = ''
      nix flake check
    '';
    impure = true;
  };
  tasks.update.inputs = pkgs.ci.command {
    name = "flake-update";
    displayName = "nix flake update";
    cache.enable = false;
    allowSubstitutes = false;
    inherit (builtins) currentTime; # dirty on every evaluation
    command = ''
      nix flake update --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable-small
      git --no-pager diff flake.lock
    '';
    impure = true;
  };
  tasks.push.inputs = pkgs.ci.command rec {
    name = "git-push";
    displayName = "git push: flake.nix";
    skip =
      if env.gh-event-name or null != "schedule" then "only scheduled"
      else if env.git-branch != "main" then "branch"
      else false;
    depends = [
      config.tasks.update.drv
      config.tasks.check.drv
    ];
    cache.enable = false;
    allowSubstitutes = false;
    GIT_COMMITTER_EMAIL = "ghost@konpaku.2hu";
    GIT_COMMITTER_NAME = "ghost";
    GIT_AUTHOR_EMAIL = GIT_COMMITTER_EMAIL;
    GIT_AUTHOR_NAME = GIT_COMMITTER_NAME;
    gitBranch = env.git-branch;
    command = ''
      if [[ -n $(git status --porcelain flake.lock) ]] && git diff flake.lock | grep -qF nvidia-patch; then
        git add flake.lock
        git commit -m "flake update"
        git push -q origin HEAD:$gitBranch
      fi
    '';
    impure = true;
  };
in {
  imports = [ ./ci.nix ];
  config = {
    name = mkForce "update";
    ci.gh-actions.checkoutOptions.fetch-depth = 0;
    gh-actions.on = let
      paths = [
        config.ci.gh-actions.path
        "flake.nix"
        "ci.nix"
        "derivation.nix"
      ];
    in {
      push = {
        inherit paths;
      };
      pull_request = {
        inherit paths;
      };
      schedule = singleton {
        cron = "40 8 * * *";
      };
    };
    tasks = mkForce tasks;
  };
}
