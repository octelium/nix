{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  pname ? "octelium",
}:

let
  sources = lib.importJSON ../../sources/octelium.json;
  inherit (stdenvNoCC.hostPlatform) system;

  descriptions = {
    octelium = "Connect to Octelium Clusters, access and serve their Services";
    octeliumctl = "Manage the resources of Octelium Clusters";
    octops = "Install, upgrade and operate Octelium Clusters";
  };
in

assert lib.assertOneOf "pname" pname (lib.attrNames descriptions);

stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname;
  inherit (sources) version;

  src = fetchurl {
    inherit (sources.assets.${system}.${pname} or (throw "${pname} is not available for ${system}"))
      url
      hash
      ;
  };

  sourceRoot = ".";

  nativeBuildInputs = [ installShellFiles ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${pname} $out/bin/${pname}

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform) ''
    export HOME="$(mktemp -d)"
    installShellCompletion --cmd ${pname} \
      --bash <($out/bin/${pname} completion bash) \
      --fish <($out/bin/${pname} completion fish) \
      --zsh <($out/bin/${pname} completion zsh)
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    HOME="$(mktemp -d)" $out/bin/${pname} version | grep -F "v${finalAttrs.version}"

    runHook postInstallCheck
  '';

  meta = {
    description = descriptions.${pname};
    homepage = "https://octelium.com";
    downloadPage = "https://github.com/octelium/octelium/releases";
    changelog = "https://github.com/octelium/octelium/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames sources.assets;
    mainProgram = pname;
  };
})
