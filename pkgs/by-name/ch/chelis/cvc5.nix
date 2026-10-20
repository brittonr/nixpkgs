{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  runCommand,
  cvc5,
  cadical,
  gmp,
  libpoly,
}:
let
  # Match cvc5-sys 0.3.1: Production, static libraries, LibPoly, and no GPL code.
  version = "1.3.1";
  source = fetchFromGitHub {
    owner = "cvc5";
    repo = "cvc5";
    tag = "cvc5-${version}";
    hash = "sha256-nxJjrpWZfYPuuKN4CWxOHEuou4r+MdK0AjdEPZHZbHI=";
  };
  gmpStatic = gmp.override { withStatic = true; };
  cadicalStatic = (cadical.override { version = "2.1.3"; }).overrideAttrs {
    src = fetchFromGitHub {
      owner = "arminbiere";
      repo = "cadical";
      rev = "a384d221a920d473b770df6a7221f35fc5d99e90";
      hash = "sha256-2z65Fplm75p4nzTdjH9pKBRJC+sWZewIerTUT/nOdJM=";
    };
    configurePhase = ''
      runHook preConfigure
      ./configure --quiet --no-contrib -fPIC CXXFLAGS="-std=c++11"
      runHook postConfigure
    '';
    doCheck = false;
  };
  polyStatic = (libpoly.override { gmp = gmpStatic; }).overrideAttrs {
    version = "0.2.0";
    src = fetchFromGitHub {
      owner = "SRI-CSL";
      repo = "libpoly";
      tag = "v0.2.0";
      hash = "sha256-gE2O1YfiVab/aIqheoMP8GhE+N3yho7kb5EP56pzjW8=";
    };
    cmakeFlags = [
      "-DLIBPOLY_BUILD_PYTHON_API=OFF"
      "-DLIBPOLY_BUILD_STATIC=OFF"
      "-DLIBPOLY_BUILD_STATIC_PIC=ON"
      "-DBUILD_TESTING=OFF"
      "-DGMP_INCLUDE_DIR=${gmpStatic.dev}/include"
      "-DGMP_LIBRARY=${gmpStatic}/lib/libgmp.a"
    ];
    buildFlags = [
      "static_pic_poly"
      "static_pic_polyxx"
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib" "$out/include/poly/polyxx"
      cp src/libpicpoly.a src/libpicpolyxx.a "$out/lib/"
      cp ../include/*.h "$out/include/poly/"
      cp ../include/polyxx/*.h "$out/include/poly/polyxx/"
      runHook postInstall
    '';
  };
  symfpuHeaders = stdenv.mkDerivation {
    pname = "symfpu-cvc5";
    version = "0-unstable-2023-06-27";
    src = fetchurl {
      url = "https://github.com/cvc5/symfpu/archive/e6ac3af9c2c574498ea171c957425b407625448b.tar.gz";
      hash = "sha256-gjqmY/zC9oRK5enqg87aTtOTzbPa3vzps8fEHND09wI=";
    };
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/include/symfpu"
      cp -R core utils "$out/include/symfpu/"
      runHook postInstall
    '';
  };
  solver =
    (cvc5.override {
      gmp = gmpStatic;
      cadical' = cadicalStatic;
      libpoly = polyStatic;
      symfpu = symfpuHeaders;
    }).overrideAttrs
      (old: {
        inherit version;
        src = source;
        buildInputs = [
          cadicalStatic.dev
          gmpStatic
          polyStatic
          symfpuHeaders
        ];
        postPatch = ''
          substituteInPlace cmake/FindGMP.cmake --replace-fail \
            'LINK_LIBRARIES ''${GMP_LIBRARIES} ''${GMPXX_LIBRARIES}' \
            'LINK_LIBRARIES ''${GMPXX_LIBRARIES} ''${GMP_LIBRARIES}'
        '';
        cmakeBuildType = "Production";
        cmakeFlags = [
          "-DBUILD_SHARED_LIBS=OFF"
          "-DENABLE_AUTO_DOWNLOAD=OFF"
          "-DBUILD_GMP=OFF"
          "-DENABLE_GPL=OFF"
          "-DUSE_CLN=OFF"
          "-DUSE_POLY=ON"
          "-DCaDiCaL_INCLUDE_DIR=${cadicalStatic.dev}/include"
          "-DCaDiCaL_LIBRARIES=${cadicalStatic.lib}/lib/libcadical.a"
          "-DGMP_INCLUDE_DIR=${gmpStatic.dev}/include"
          "-DGMPXX_INCLUDE_DIR=${gmpStatic.dev}/include"
          "-DGMP_LIBRARIES=${gmpStatic}/lib/libgmp.a"
          "-DGMPXX_LIBRARIES=${gmpStatic}/lib/libgmpxx.a"
          "-DPoly_INCLUDE_DIR=${polyStatic}/include"
          "-DPoly_LIBRARIES=${polyStatic}/lib/libpicpoly.a"
          "-DPolyXX_LIBRARIES=${polyStatic}/lib/libpicpolyxx.a"
          "-DSymFPU_INCLUDE_DIR=${symfpuHeaders}/include"
          "-DSTATIC_BINARY=OFF"
        ];
        doCheck = false;
        meta = old.meta // {
          license = with lib.licenses; [
            bsd3
            mit
            lgpl3Plus
          ];
        };
      });
in
# cvc5-sys checks the version and archive before it decides to build or download.
runCommand "cvc5-${version}-rust-tree" { } ''
  mkdir -p "$out/cmake" "$out/build/src/parser" "$out/build/deps/lib"
  ln -s ${source}/cmake/version-base.cmake "$out/cmake/version-base.cmake"
  ln -s ${solver}/include "$out/include"
  ln -s ${solver}/include "$out/build/include"
  ln -s ${solver}/lib/libcvc5.a "$out/build/src/libcvc5.a"
  ln -s ${solver}/lib/libcvc5parser.a "$out/build/src/parser/libcvc5parser.a"
  ln -s ${cadicalStatic.lib}/lib/libcadical.a "$out/build/deps/lib/libcadical.a"
  ln -s ${polyStatic}/lib/libpicpoly.a "$out/build/deps/lib/libpicpoly.a"
  ln -s ${polyStatic}/lib/libpicpolyxx.a "$out/build/deps/lib/libpicpolyxx.a"
  ln -s ${gmpStatic}/lib/libgmp.a "$out/build/deps/lib/libgmp.a"
  grep -Fx 'set(CVC5_LAST_RELEASE "${version}")' "$out/cmake/version-base.cmake"
  for archive in "$out/build/src/libcvc5.a" "$out/build/src/parser/libcvc5parser.a" "$out"/build/deps/lib/*.a; do
    test -s "$archive"
  done
''
