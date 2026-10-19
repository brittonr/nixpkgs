{
  lib,
  stdenv,
  runCommand,
  python3,
  openblas,
  chelis,
}:
let
  bare = "env -i PATH=/var/empty HOME=$TMPDIR TMPDIR=$TMPDIR";
  toolchainPath = lib.makeBinPath [
    stdenv.cc
    stdenv.cc.bintools
  ];
in
{
  runtime = runCommand "chelis-runtime-consumer" {
    nativeBuildInputs = [ stdenv.cc ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ openblas ];
  } ''
    ${chelis}/bin/chelis runtime export "$TMPDIR/export"
    ${python3.interpreter} ${chelis.src}/scripts/verify_runtime_package.py \
      "$TMPDIR/export" ${chelis}
    cc -std=c11 -Wall -Wextra -Werror -I${chelis}/include \
      ${./runtime-consumer.c} ${chelis}/lib/libchelis_runtime.a \
      ${if stdenv.hostPlatform.isDarwin then "-framework Accelerate" else "-lopenblas -lm -lpthread -ldl"} \
      -o consumer
    ./consumer

    # A changed installed header must fail the export comparison.
    mkdir altered
    cp -R ${chelis}/include ${chelis}/lib altered/
    chmod -R u+w altered
    printf '\n#define CHELIS_PACKAGE_TEST 1\n' >> altered/include/chelis_runtime_views.h
    if ${python3.interpreter} ${chelis.src}/scripts/verify_runtime_package.py \
      "$TMPDIR/export" altered; then
      echo 'The altered header passed the runtime comparison' >&2
      exit 1
    fi
    touch "$out"
  '';

  build = runCommand "chelis-wrapped-build" { } ''
    cp ${chelis.src}/examples/{hello_tensor,native_library,recurrence_extent_scope}.ch .
    chmod u+w *.ch
    ${bare} ${chelis}/bin/chelis build hello_tensor.ch -o hello
    test "$(${bare} ./hello/hello_tensor)" = \
      'main = tensor(shape=[3], data=[5.0, 7.0, 9.0])'
    ${bare} ${chelis}/bin/chelis build native_library.ch -o library
    test "$(head -c 8 library/libnative_library.a)" = '!<arch>'
    ${bare} ${chelis}/bin/chelis build recurrence_extent_scope.ch -o blas
    grep -q '#include "chelis_blas.h"' blas/recurrence_extent_scope.c
    test "$(${bare} ./blas/recurrence_extent_scope)" = \
      "$(printf 'main.0 = 40.0\nmain.1 = Model([5.0, 5.0])')"

    status=0
    ${bare} ${chelis}/libexec/chelis build hello_tensor.ch -o no-compiler \
      2>no-compiler.log || status=$?
    test "$status" -ne 0
    grep -q 'was not found' no-compiler.log
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      status=0
      env -i PATH=${toolchainPath}:/var/empty HOME=$TMPDIR TMPDIR=$TMPDIR \
        ${chelis}/libexec/chelis build recurrence_extent_scope.ch -o no-blas \
        2>no-blas.log || status=$?
      test "$status" -ne 0
      grep -Eq 'cblas\.h|lopenblas' no-blas.log
    ''}
    touch "$out"
  '';

  release = runCommand "chelis-release-behavior" {
    nativeBuildInputs = [ python3 ];
  } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" source
    cp -R ${chelis.src}/. source/
    chmod -R u+w source
    cd source
    test "$(${chelis}/bin/chelis --version)" = 'chelis ${chelis.version}'
    ${chelis}/bin/chelis --help >/dev/null
    (
      cd crates/chelis-cli/tests/fixtures/release_pipe_stage
      ${chelis}/bin/chelis test tests
    )
    python3 .github/scripts/verify_release_smt.py --clarabel ${chelis}/bin/chelis
    touch "$out"
  '';
}
