{ pkgs }:

let
  inherit (pkgs) callPackage symlinkJoin;

  octelium = callPackage ./octelium/package.nix { pname = "octelium"; };
  octeliumctl = callPackage ./octelium/package.nix { pname = "octeliumctl"; };
  octops = callPackage ./octelium/package.nix { pname = "octops"; };
  octelium-desktop = callPackage ./octelium-desktop/package.nix { };

  octelium-tools = symlinkJoin {
    name = "octelium-tools-${octelium.version}";
    inherit (octelium) version;
    paths = [
      octelium
      octeliumctl
      octops
    ];
    meta = octelium.meta // {
      description = "Octelium command-line tools: octelium, octeliumctl and octops";
    };
  };

  octelium-all = symlinkJoin {
    name = "octelium-all-${octelium.version}";
    inherit (octelium) version;
    paths = [
      octelium-tools
      octelium-desktop
    ];
    meta = octelium.meta // {
      description = "Octelium command-line tools and Octelium Desktop";
      inherit (octelium-desktop.meta) platforms;
    };
  };
in

{
  inherit
    octelium
    octeliumctl
    octops
    octelium-tools
    octelium-desktop
    octelium-all
    ;
}
