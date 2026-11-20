{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  patchelf,
  glibc,
  makeBinaryWrapper,
  versionCheckHook,
  ripgrep,
  netcat,
  useMusl ? false,
  binName ? "agy",
  extraRuntimeInputs ? [ ],
}:
let
  inherit (lib.lists) optional optionals singleton;
  inherit (lib.strings) makeBinPath optionalString;
  inherit (lib.trivial) importJSON;

  sources = importJSON ./sources.json;
  inherit (sources) version;

  system = stdenvNoCC.hostPlatform.system;
  isLinux = stdenvNoCC.hostPlatform.isLinux;

  variant =
    if !isLinux then
      "darwin"
    else if useMusl then
      "musl"
    else
      "glibc";

  platformSources =
    sources.platforms.${system} or (throw "antigravity-cli: unsupported system ${system}");

  asset =
    platformSources.${variant}
      or (throw "antigravity-cli: unsupported variant ${variant} on ${system}");

  useAutoPatchelf = stdenvNoCC.hostPlatform.isElf && variant == "glibc";

  runtimePath = makeBinPath (
    [
      ripgrep
      netcat
    ]
    ++ extraRuntimeInputs
  );
in
stdenvNoCC.mkDerivation {
  pname = if isLinux && variant == "musl" then "antigravity-cli-musl" else "antigravity-cli";
  inherit version;

  strictDeps = true;
  __structuredAttrs = true;

  # GCS is the direct origin; GitHub Releases serves byte-identical archives
  # as a fallback mirror verified against the same SHA-512 hash.
  src = fetchurl {
    urls = [
      asset.gcsUrl
      "https://github.com/google-antigravity/antigravity-cli/releases/download/${version}/${asset.githubAsset}"
    ];
    inherit (asset) hash;
  };

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  # Preserves Darwin code signatures and embedded Go/sidecar payloads.
  dontStrip = true;
  dontPatchELF = !useAutoPatchelf;

  nativeBuildInputs =
    singleton makeBinaryWrapper
    ++ optionals useAutoPatchelf [
      autoPatchelfHook
      patchelf
    ];

  buildInputs = optional useAutoPatchelf glibc;

  # autoPatchelfHook sets PT_INTERP but omits glibc from DT_RUNPATH because
  # ld-linux has a built-in fallback; without an explicit DT_RUNPATH, hosts
  # running envfs (/lib -> /usr/lib) resolve libc.so.6 via /lib instead of
  # the pinned glibc in /nix/store.
  preFixup = optionalString useAutoPatchelf /* bash */ ''
    postFixupHooks+=('patchelf --add-rpath "${glibc}/lib" "$out/libexec/agy"')
  '';

  installPhase = /* bash */ ''
    runHook preInstall

    install -Dm755 antigravity "$out/libexec/agy"

    makeBinaryWrapper "$out/libexec/agy" "$out/bin/${binName}" \
      --inherit-argv0 \
      --suffix PATH : "${runtimePath}"

    runHook postInstall
  '';

  nativeInstallCheckInputs = singleton versionCheckHook ++ optional useAutoPatchelf patchelf;

  versionCheckProgram = "${placeholder "out"}/bin/${binName}";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  preInstallCheck = optionalString useAutoPatchelf /* bash */ ''
    rpath=$(patchelf --print-rpath "$out/libexec/agy")
    case ":$rpath:" in
      *":${glibc}/lib:"*) ;;
      *)
        echo "antigravity-cli: missing ${glibc}/lib in DT_RUNPATH ($rpath)" >&2
        exit 1
        ;;
    esac
  '';

  passthru = {
    inherit sources useMusl variant;
  };

  meta = {
    description =
      "Google Antigravity terminal agent CLI"
      + optionalString (isLinux && variant == "musl") " (static musl build)";
    homepage = "https://antigravity.google/product/antigravity-cli";
    changelog = "https://github.com/google-antigravity/antigravity-cli/blob/main/CHANGELOG.md";
    license = lib.licenses.unfree;
    sourceProvenance = singleton lib.sourceTypes.binaryNativeCode;
    platforms =
      if useMusl then
        [
          "x86_64-linux"
          "aarch64-linux"
        ]
      else
        [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];
    mainProgram = binName;
  };
}
