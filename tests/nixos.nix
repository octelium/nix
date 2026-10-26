{ pkgs, module }:

pkgs.testers.runNixOSTest {
  name = "octelium";

  nodes = {
    owned =
      { config, ... }:
      {
        imports = [ module ];

        programs.octelium.enable = true;
        programs.octelium-desktop = {
          enable = true;
          autostart = true;
          daemon.owner = config.users.users.alice.uid;
        };

        users.users.alice = {
          isNormalUser = true;
          uid = 1000;
        };
      };

    desktop = {
      imports = [
        module
        (pkgs.path + "/nixos/tests/common/x11.nix")
      ];

      programs.octelium-desktop.enable = true;

      virtualisation.memorySize = 2048;
    };
  };

  testScript =
    { nodes, ... }:
    let
      octeliumVersion = nodes.owned.programs.octelium-desktop.daemon.package.version;
    in
    ''
      start_all()

      with subtest("the daemon runs and serves the local API"):
          owned.wait_for_unit("octelium-desktop-daemon.service")
          owned.wait_for_file("/run/octelium/daemon.sock")
          owned.succeed("test \"$(stat -c %a /run/octelium/daemon.sock)\" = 666")
          owned.succeed("test \"$(stat -c %a /var/lib/octelium-desktop)\" = 700")

      with subtest("the daemon is bound to its owner"):
          owned.wait_for_file("/home/alice/.config/octelium/octelium.db")
          for path in [".config", ".config/octelium", ".config/octelium/octelium.db"]:
              owned.succeed(f"test \"$(stat -c %U /home/alice/{path})\" = alice")

      with subtest("the daemon is not restarted"):
          owned.sleep(10)
          owned.succeed("test \"$(systemctl show -P NRestarts octelium-desktop-daemon.service)\" = 0")

      with subtest("the command-line tools are installed"):
          for cli in ["octelium", "octeliumctl", "octops"]:
              owned.succeed(f"su - alice -c '{cli} version' | grep -F v${octeliumVersion}")
              owned.succeed(f"test -f /run/current-system/sw/share/bash-completion/completions/{cli}.bash")

      with subtest("the autostart entry is installed"):
          owned.succeed("grep -Fx Exec=octelium-desktop /etc/xdg/autostart/octelium-desktop.desktop")

      with subtest("the application connects to the daemon"):
          desktop.wait_for_x()
          desktop.wait_for_unit("octelium-desktop-daemon.service")
          desktop.succeed("${pkgs.dbus}/bin/dbus-run-session -- sh -c 'echo $$ > /tmp/octelium-desktop.pid; exec octelium-desktop' >&2 &")
          desktop.wait_for_file("/root/.config/octelium/octelium.db", timeout=120)
          desktop.sleep(5)
          desktop.succeed("kill -0 $(cat /tmp/octelium-desktop.pid)")
          desktop.screenshot("octelium-desktop")
    '';
}
