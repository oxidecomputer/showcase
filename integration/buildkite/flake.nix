{
  description = "oxide-buildkite-stack";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
          (system: f (import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = package:
              nixpkgs.lib.getName package == "packer";
          }));
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ go_1_27 gopls gotools gnumake packer shellcheck ];
        };
      });
    };
}
