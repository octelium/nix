# Octelium Nix

Nix packages and a NixOS module for [Octelium](https://github.com/octelium/octelium) and [Octelium Desktop](https://github.com/octelium/octelium-desktop).

## Packages

| Package | Contents | Platforms |
| --- | --- | --- |
| `octelium-tools` (default) | `octelium`, `octeliumctl` and `octops` | Linux, macOS |
| `octelium` | The `octelium` CLI | Linux, macOS |
| `octeliumctl` | The `octeliumctl` CLI | Linux, macOS |
| `octops` | The `octops` CLI | Linux, macOS |
| `octelium-desktop` | The Octelium Desktop application | Linux |
| `octelium-all` | `octelium-tools` and `octelium-desktop` | Linux |

The packages are built from the official release artifacts of every Octelium release for `x86_64` and `aarch64`. They ship the shell completions for bash, zsh and fish.

## Install the CLIs

Run the `octelium` CLI without installing it:

```bash
nix run github:octelium/nix#octelium -- version
```

Install the `octelium`, `octeliumctl` and `octops` CLIs to your profile:

```bash
nix profile add github:octelium/nix
```

Use `nix profile install` instead with older Nix versions. You can also install a single CLI, for example `nix profile add github:octelium/nix#octeliumctl`.

Upgrade them later as follows:

```bash
nix profile upgrade --all
```

## NixOS

Add the flake to your system flake and enable the module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    octelium = {
      url = "github:octelium/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, octelium, ... }:
    {
      nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          octelium.nixosModules.default
          {
            programs.octelium.enable = true;
            programs.octelium-desktop.enable = true;
          }
        ];
      };
    };
}
```

`programs.octelium.enable` installs the CLIs. `programs.octelium-desktop.enable` installs Octelium Desktop and runs its privileged daemon as the `octelium-desktop-daemon` systemd service. Both can be enabled independently.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `programs.octelium.enable` | `false` | Install the Octelium CLIs. |
| `programs.octelium.package` | `octelium-tools` | The package of the CLIs. Set it to `octelium` to install the `octelium` CLI alone. |
| `programs.octelium-desktop.enable` | `false` | Install Octelium Desktop and run its daemon. |
| `programs.octelium-desktop.package` | `octelium-desktop` | The Octelium Desktop package. |
| `programs.octelium-desktop.autostart` | `false` | Start Octelium Desktop on graphical login via a system-wide XDG autostart entry. |
| `programs.octelium-desktop.daemon.package` | `octelium` | The package providing the `octelium` executable that runs the daemon. |
| `programs.octelium-desktop.daemon.owner` | `null` | The UID of the OS user that owns the daemon, e.g. `1000`. By default, the daemon is owned by the OS user of its first local API caller. |
| `programs.octelium-desktop.daemon.extraArgs` | `[ ]` | Extra arguments passed to `octelium daemon`. |

### The daemon

Octelium Desktop does not connect to Clusters by itself. It controls the local Octelium daemon, `octelium daemon`, which runs as root since it owns the host networking configuration of the Connections. The module runs the daemon the same way the official Debian, RPM and Arch Linux packages do:

- The daemon is the `octelium-desktop-daemon` systemd service. It is started on boot and restarted on failure.
- It serves the local API at `/run/octelium/daemon.sock`. Every local API call from an OS user other than the owner of the daemon is rejected.
- It stores the credentials and the settings of its owner in the Octelium home directory of the owner, i.e. `~/.config/octelium`.
- It runs from the `octelium` package of this flake rather than a copy bundled with Octelium Desktop. The module asserts that this package is at least the Octelium version that the Octelium Desktop release was built against.

To bind the daemon to a specific user, set an explicit UID:

```nix
{ config, ... }:
{
  users.users.alice = {
    isNormalUser = true;
    uid = 1000;
  };

  programs.octelium-desktop.daemon.owner = config.users.users.alice.uid;
}
```

An automatically allocated UID is `null` during Nix evaluation. Referencing it as the daemon owner leaves the daemon owned by its first local API caller.

You can inspect it as follows:

```bash
systemctl status octelium-desktop-daemon
journalctl -u octelium-desktop-daemon
```

The daemon configures the DNS of the Connections via systemd-resolved when it is running and falls back to `/etc/resolv.conf` otherwise. Enabling `services.resolved.enable` is recommended.

Prefer the `autostart` option to the start-on-login setting of the application. The application writes its current Nix store path to the autostart entry of the user and that entry stops working once that store path is garbage collected.

## Other Linux distributions

The `octelium-desktop` package only contains the application, since Nix cannot install system services outside of NixOS. Use the official [Debian, RPM or Arch Linux packages](https://octelium.com/docs) of Octelium Desktop on other Linux distributions, or run `sudo octelium daemon` yourself before starting the application.

## nix-darwin

Pass the `octelium` flake input through `specialArgs` and add the packages directly:

```nix
{ pkgs, octelium, ... }:
{
  environment.systemPackages = [ octelium.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
```

Or use the overlay:

```nix
{ pkgs, octelium, ... }:
{
  nixpkgs.overlays = [ octelium.overlays.default ];
  environment.systemPackages = [ pkgs.octelium-tools ];
}
```

The overlay builds the packages with your own nixpkgs. It also supports `x86_64-darwin` with nixpkgs releases that still support it.

## Home Manager

Pass the `octelium` flake input through `extraSpecialArgs` and add the packages directly:

```nix
{ pkgs, octelium, ... }:
{
  home.packages = [ octelium.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
```

Or use the overlay:

```nix
{ pkgs, octelium, ... }:
{
  nixpkgs.overlays = [ octelium.overlays.default ];
  home.packages = [ pkgs.octelium-tools ];
}
```

## Without flakes

```nix
let
  octelium = import (fetchTarball "https://github.com/octelium/nix/archive/main.tar.gz") { };
in
{
  environment.systemPackages = [ octelium.octelium-tools ];
}
```

The NixOS module is available at `modules/nixos` of the repository.

## Updates

The versions, URLs and hashes of the release artifacts are stored in [`sources/octelium.json`](sources/octelium.json) and [`sources/octelium-desktop.json`](sources/octelium-desktop.json). They are generated by [`scripts/update.sh`](scripts/update.sh), which verifies every release artifact before using it:

- Its SHA-256 digest must match the digest in the `SHA256SUMS` file of the release.
- Its SHA-256 digest must match the digest of the release asset reported by GitHub.
- It must have a valid [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) signed by the `release.yaml` workflow of its repository for the tag of the release on a GitHub-hosted runner.

The [update workflow](.github/workflows/update.yaml) checks for new releases of Octelium and Octelium Desktop every 30 minutes and updates the nixpkgs input every week. Changes are checked by the [CI workflow](.github/workflows/ci.yaml) on `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`, which builds every package and runs the NixOS VM tests, before they are pushed to `main`. The update workflow can also be run manually for specific release tags or be triggered right after a release with a `release` [repository dispatch](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event) event:

```bash
gh api repos/octelium/nix/dispatches -f event_type=release
```

To update the sources locally:

```bash
nix develop -c scripts/update.sh octelium
nix develop -c scripts/update.sh octelium-desktop v0.2.8
```

## Development

```bash
nix flake check
nix fmt
```

`nix flake check` builds every package and runs the formatting, lint, update script and NixOS VM tests.

## License

Apache License 2.0. See [LICENSE](LICENSE).
