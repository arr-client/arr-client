# Development shell for arr-client (NixOS and any Linux or macOS machine with Nix).
#
#   nix-shell                              Flutter, Android SDK, JDK and repository tools
#   nix-shell --arg withEmulator true      also an Android emulator and system image (large)
#
# The Android SDK needs you to accept its licences (https://developer.android.com/studio/terms and
# the preview, Google TV, XR, GDK, Intel, MIPS and ARM translation licences listed below). Set
# NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1 to do so; .envrc does this for direnv users.
{ withEmulator ? false }:

let
  acceptLicenses = builtins.getEnv "NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE" == "1";

  # nixos-unstable, pinned so every contributor gets Flutter 3.50.1 / Dart 3.14.0.
  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/2786a2a72088ecf32aea5b3ec52099e6a7cff78f.tar.gz";
    sha256 = "0fm3lxj743j3ksdhs31lb2sn9bkix3kvam2qb4hc8ipr2yzmbxbz";
  };
  pkgs = import nixpkgs {
    config = {
      allowUnfree = true;
      android_sdk.accept_license = acceptLicenses;
    };
  };

  # The Nix store is read-only, so Gradle cannot download missing parts: list them all here.
  buildTools = "37.0.0";
  android = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "36" "37.0" ]; # 36: Flutter 3.50 default, used by plugins; 37: our target
    buildToolsVersions = [ "36.0.0" buildTools ];
    includeNDK = true;
    ndkVersions = [ "28.2.13676358" ]; # Flutter 3.50 default
    cmakeVersions = [ "3.22.1" ];
    includeEmulator = withEmulator;
    includeSystemImages = withEmulator;
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
    # The store is read-only, so `flutter doctor --android-licenses` cannot save an answer.
    # These are the licences it asks about besides android-sdk-license.
    extraLicenses = pkgs.lib.optionals acceptLicenses [
      "android-googletv-license"
      "android-googlexr-license"
      "android-sdk-arm-dbt-license"
      "android-sdk-preview-license"
      "google-gdk-license"
      "intel-android-extra-license"
      "intel-android-sysimage-license"
      "microxr-sysimage-license"
      "mips-android-sysimage-license"
    ];
  };
  sdk = "${android.androidsdk}/libexec/android-sdk";
in
pkgs.mkShell {
  packages = [
    pkgs.flutter350
    pkgs.jdk17
    android.androidsdk
    pkgs.git
    pkgs.gh
    pkgs.python3 # .github/scripts
    pkgs.actionlint
    pkgs.uv # to run GitHub Spec Kit's `specify`
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.chromium ];

  ANDROID_HOME = sdk;
  ANDROID_SDK_ROOT = sdk;
  JAVA_HOME = pkgs.jdk17.home;
  # Web is not a release target; this is for `flutter run -d chrome` or `-d web-server` and doctor.
  CHROME_EXECUTABLE = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "${pkgs.chromium}/bin/chromium";
  # The aapt2 that Gradle downloads from Maven does not run on NixOS.
  GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdk}/build-tools/${buildTools}/aapt2";
}
