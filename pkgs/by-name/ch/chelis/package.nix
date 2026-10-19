{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  callPackage,
  makeBinaryWrapper,
  openblas,
  python3,
  testers,
}:
let
  cvc5Tree = callPackage ./cvc5.nix { };
  runtimeHeaders = [
    "chelis_runtime.h"
    "chelis_runtime_views.h"
    "chelis_runtime_dtype.h"
    "chelis_blas.h"
    "chelis_simd.h"
    "chelis_math.h"
  ];
  wrapperArgs = [
    "--prefix" "PATH" ":" (lib.makeBinPath [ stdenv.cc stdenv.cc.bintools ])
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    "--prefix" "CHELIS_C_INCLUDE_PATH" ":" "${lib.getDev openblas}/include"
    "--prefix" "CHELIS_C_LIBRARY_PATH" ":" "${lib.getLib openblas}/lib"
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "chelis";
  version = "0.21.0";

  src = fetchFromGitHub {
    owner = "Chelis-Lang";
    repo = "chelis";
    tag = "v${finalAttrs.version}";
    hash = "sha256-jZ5/qd/ZJX3DXvNOxcZ7PegybFWm24QqWre9AZLFXu4=";
  };

  cargoHash = "sha256-5JHEehHHXVy6Qf5pCCVesI8KnIkmX703xjLbVWcMTlg=";

  nativeBuildInputs = [
    makeBinaryWrapper
    rustPlatform.bindgenHook
  ];

  cargoBuildFlags = [ "--package=chelis-cli" "--bin=chelis" ];
  buildNoDefaultFeatures = true;
  buildFeatures = [ "distribution" ];
  cargoTestFlags = [ "--package=chelis-cli" "--bins" ];

  env = {
    CVC5_DIR = "${cvc5Tree}";
    CARGO_INCREMENTAL = "0";
    CARGO_PROFILE_DEV_DEBUG = "0";
    CARGO_PROFILE_TEST_DEBUG = "0";
    CARGO_PROFILE_RELEASE_DEBUG = "0";
  };

  # The installed archive must remain byte-identical to the compiler export.
  stripDebugList = [ "bin" "libexec" ];

  postInstall = ''
    export_dir="$TMPDIR/runtime-export"
    $out/bin/chelis runtime export "$export_dir"
    install -Dm444 "$export_dir/libchelis_runtime.a" "$out/lib/libchelis_runtime.a"
    ${lib.concatMapStringsSep "\n" (header: ''
      install -Dm444 "$export_dir/${header}" "$out/include/${header}"
    '') runtimeHeaders}
    ${python3.interpreter} scripts/verify_runtime_package.py "$export_dir" "$out"
    mkdir -p "$out/libexec"
    mv "$out/bin/chelis" "$out/libexec/chelis"
    makeBinaryWrapper "$out/libexec/chelis" "$out/bin/chelis" \
      ${lib.escapeShellArgs wrapperArgs}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ python3 ];
  installCheckPhase = ''
    runHook preInstallCheck
    test "$($out/bin/chelis --version)" = 'chelis ${finalAttrs.version}'
    $out/bin/chelis runtime export "$TMPDIR/installed-export"
    python3 scripts/verify_runtime_package.py "$TMPDIR/installed-export" "$out"
    runHook postInstallCheck
  '';

  passthru.tests = (callPackage ./tests.nix { chelis = finalAttrs.finalPackage; }) // {
    version = testers.testVersion { package = finalAttrs.finalPackage; };
  };

  meta = {
    description = "Numerical language with typed tensor shapes and checked properties";
    homepage = "https://chelis.ch";
    changelog = "https://github.com/Chelis-Lang/chelis/releases/tag/v${finalAttrs.version}";
    # Chelis is MIT. Clarabel, cvc5, LibPoly, and static GMP keep their licenses.
    license = with lib.licenses; [ mit asl20 bsd3 lgpl3Plus ];
    maintainers = [ lib.maintainers.brittonr ];
    mainProgram = "chelis";
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
  };
})
