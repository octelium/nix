{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.programs.octelium;
  desktopCfg = config.programs.octelium-desktop;
  octeliumPkgs = import ../../pkgs { inherit pkgs; };
  minimumOcteliumVersion = desktopCfg.package.minimumOcteliumVersion or null;
in

{
  options.programs.octelium = {
    enable = lib.mkEnableOption "the Octelium command-line tools";

    package = lib.mkOption {
      type = lib.types.package;
      default = octeliumPkgs.octelium-tools;
      defaultText = lib.literalMD "`octelium-tools` of the Octelium flake";
      example = lib.literalMD "`octelium` of the Octelium flake to install the `octelium` CLI alone";
      description = "The package providing the Octelium command-line tools.";
    };
  };

  options.programs.octelium-desktop = {
    enable = lib.mkEnableOption "Octelium Desktop and its privileged daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = octeliumPkgs.octelium-desktop;
      defaultText = lib.literalMD "`octelium-desktop` of the Octelium flake";
      description = "The Octelium Desktop package.";
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to start Octelium Desktop on graphical login via a system-wide
        XDG autostart entry. Prefer this option to the start-on-login setting of
        the application since the application writes its current Nix store path
        to the autostart entry of the user which breaks once that store path is
        garbage collected.
      '';
    };

    daemon = {
      package = lib.mkOption {
        type = lib.types.package;
        default = octeliumPkgs.octelium;
        defaultText = lib.literalMD "`octelium` of the Octelium flake";
        description = "The package providing the `octelium` executable that runs the daemon.";
      };

      owner = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        example = 1000;
        description = ''
          The UID of the OS user that owns the daemon. The local API calls of
          every other OS user are rejected. By default, the daemon is owned by
          the OS user of its first local API caller. When referencing
          `config.users.users.<name>.uid`, explicitly set that user's UID since
          an automatically allocated UID is `null` during evaluation.
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "--state-dir"
          "/var/lib/octelium-desktop/state"
        ];
        description = "Extra arguments passed to `octelium daemon`.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    })

    (lib.mkIf desktopCfg.enable {
      assertions = [
        {
          assertion =
            minimumOcteliumVersion == null
            || lib.versionAtLeast desktopCfg.daemon.package.version minimumOcteliumVersion;
          message = "Octelium Desktop ${desktopCfg.package.version} requires programs.octelium-desktop.daemon.package to be Octelium ${toString minimumOcteliumVersion} or later but it is ${desktopCfg.daemon.package.version}.";
        }
      ];

      environment.systemPackages = [ desktopCfg.package ];

      environment.etc."xdg/autostart/octelium-desktop.desktop" = lib.mkIf desktopCfg.autostart {
        source = "${desktopCfg.package}/share/applications/octelium-desktop.desktop";
      };

      systemd.services.octelium-desktop-daemon = {
        description = "Octelium Desktop daemon";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment.OCTELIUM_HOME = "/var/lib/octelium-desktop";

        serviceConfig = {
          Type = "simple";
          ExecStart = utils.escapeSystemdExecArgs (
            [
              (lib.getExe' desktopCfg.daemon.package "octelium")
              "daemon"
            ]
            ++ lib.optionals (desktopCfg.daemon.owner != null) [
              "--owner"
              (toString desktopCfg.daemon.owner)
            ]
            ++ desktopCfg.daemon.extraArgs
          );
          StateDirectory = "octelium-desktop";
          StateDirectoryMode = "0700";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    })
  ];
}
