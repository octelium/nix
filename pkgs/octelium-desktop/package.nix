{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  wrapGAppsHook3,
  cairo,
  dbus,
  gdk-pixbuf,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  libayatana-appindicator,
  libsoup_3,
  webkitgtk_4_1,
  xdg-utils,
}:

let
  sources = lib.importJSON ../../sources/octelium-desktop.json;
  inherit (stdenv.hostPlatform) system;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "octelium-desktop";
  inherit (sources) version;

  src = fetchurl {
    inherit (sources.assets.${system} or (throw "octelium-desktop is not available for ${system}"))
      url
      hash
      ;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    wrapGAppsHook3
  ];

  buildInputs = [
    cairo
    dbus
    gdk-pixbuf
    glib
    glib-networking
    gsettings-desktop-schemas
    gtk3
    libsoup_3
    (lib.getLib stdenv.cc.cc)
    webkitgtk_4_1
  ];

  runtimeDependencies = [ (lib.getLib libayatana-appindicator) ];

  unpackPhase = ''
    runHook preUnpack

    dpkg-deb --extract $src .

    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 usr/bin/octelium-desktop $out/bin/octelium-desktop
    install -Dm644 usr/share/applications/*.desktop $out/share/applications/octelium-desktop.desktop
    cp -r usr/share/icons $out/share/icons

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ xdg-utils ]})
  '';

  passthru = {
    inherit (sources) minimumOcteliumVersion;
  };

  meta = {
    description = "Octelium desktop application to authenticate to and connect to Octelium Clusters";
    longDescription = ''
      Octelium Desktop controls the local privileged Octelium daemon in order
      to authenticate to and connect to Octelium Clusters. The daemon is not
      part of this package. On NixOS, enable `programs.octelium-desktop` from
      the Octelium NixOS module which runs the daemon as a system service.
    '';
    homepage = "https://github.com/octelium/octelium-desktop";
    downloadPage = "https://github.com/octelium/octelium-desktop/releases";
    changelog = "https://github.com/octelium/octelium-desktop/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames sources.assets;
    mainProgram = "octelium-desktop";
  };
})
