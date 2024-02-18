{ lib
, buildPgrxExtension
, callPackage
, cargo-pgrx
, clang_16
, fetchCrate
, fetchFromGitHub
, nix-update-script
, nixosTests
, openssl
, pkg-config
, postgresql
, rustPlatform
}:

let
  # Upstream only works with clang 16, so we're pinning it here to
  # avoid future incompatibility.
  # See https://docs.pgvecto.rs/developers/development.html#environment, step 4
  rustPlatform' = rustPlatform // {
    inherit (callPackage ../../../../../build-support/rust/hooks {
      clang = clang_16;
    }) bindgenHook;
  };

  # Upstream only works with a fixed version of cargo-pgrx for each release,
  # so we're pinning it here to avoid future incompatibility.
  # See https://docs.pgvecto.rs/developers/development.html#environment, step 6
  cargo-pgrx_0_11_2 = cargo-pgrx.overrideAttrs (old: rec {
    name = "cargo-pgrx-${version}";
    version = "0.11.2";

    src = fetchCrate {
      pname = "cargo-pgrx";
      inherit version;
      hash = "sha256-8NlpMDFaltTIA8G4JioYm8LaPJ2RGKH5o6sd6lBHmmM=";
    };

    cargoDeps = old.cargoDeps.overrideAttrs (_: {
      inherit src;
      outputHash = "sha256-qTb3JV3u42EilaK2jP9oa5D09mkuHyRbGGRs9Rg4TzI=";
    });
  });

in
(buildPgrxExtension.override {
  cargo-pgrx = cargo-pgrx_0_11_2;
  rustPlatform = rustPlatform';
}) rec {
  inherit postgresql;

  pname = "pgvecto-rs";
  version = "0.2.0";

  buildInputs = [ openssl ];
  nativeBuildInputs = [ pkg-config clang_16 ];

  patches = [
    # Tell the `c` crate to use the flags from the rust bindgen hook
    ./0001-read-clang-flags-from-environment.diff
    # Rust feature result_option_inspect is only stabilized on Rust 1.76.0,
    # while nixpkgs is only on 1.75.0.
    ./0002-enable-feature-result-option-inspect.diff
  ];

  src = fetchFromGitHub {
    owner = "tensorchord";
    repo = "pgvecto.rs";
    rev = "v${version}";
    hash = "sha256-30AzS9R01+Ntq/HKabn+3tRHiEe68pxoVK3sbr+wFWg=";
  };

  # Package has git dependencies on Cargo.lock (instead of just crate.io dependencies),
  # so cargoHash does not work, therefore we have to include Cargo.lock in nixpkgs.
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "openai_api_rust-0.1.8" =
        "sha256-os5Y8KIWXJEYEcNzzT57wFPpEXdZ2Uy9W3j5+hJhhR4=";
      "std_detect-0.1.5" =
        "sha256-RwWejfqyGOaeU9zWM4fbb/hiO1wMpxYPKEjLO0rtRmU=";
    };
  };

  # We need to use features from rust-nightly
  RUSTC_BOOTSTRAP = 1;

  passthru = {
    updateScript = nix-update-script { };
    tests = {
      pgvecto-rs = nixosTests.pgvecto-rs;
    };
  };

  meta = with lib; {
    description =
      "Scalable Vector Search in Postgres. Revolutionize Vector Search, not Database.";
    homepage = "https://github.com/tensorchord/pgvecto.rs";
    license = licenses.asl20;
    maintainers = with maintainers; [ diogotcorreia ];
  };
}
