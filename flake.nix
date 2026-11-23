{
  description = "Local Kind + Argo CD + Gateway API development environment";

  # nixpkgs-unstable, because stable branches lag behind the kind release that
  # the pinned node image in bootstrap/kind-config.yaml was built for. flake.lock
  # pins the exact nixpkgs revision, so every tool version is reproducible.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Docker is not provided: it needs a host daemon (Docker Desktop etc).
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              # Runtime
              pkgs.just
              pkgs.kind
              pkgs.kubectl
              pkgs.curl

              # Lint (just lint)
              pkgs.kubernetes-helm
              pkgs.kubeconform
              pkgs.yamllint
              pkgs.actionlint
            ];
          };
        }
      );
    };
}
