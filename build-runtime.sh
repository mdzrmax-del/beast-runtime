#!/usr/bin/env bash
# Builds Beast runtime packages for THIS app's package name by compiling Termux's packages with a changed prefix.
#   build-runtime.sh base                      -> out/base.tar.gz (+ out/base-files.txt)
#   build-runtime.sh jdk   [base-files.txt]    -> out/jdk.tar.gz, out/gradle.tar.gz
#   build-runtime.sh tools [base-files.txt]    -> out/tools.tar.gz, out/home-android-sdk.tar.gz
# Runs on an Ubuntu GitHub runner (see .github/workflows/build.yml). Nothing here runs on the phone.
set -euo pipefail

GROUP="${1:?group: base | jdk | tools}"
BASE_LIST="${2:-}"
APP_PKG="${APP_PKG:-com.aiunify.assistant}"
ARCH=aarch64
ROOT="$PWD"
OUT="$ROOT/out"; WORK="$ROOT/work"
PREFIX_ABS="/data/data/$APP_PKG/files/usr"
mkdir -p "$OUT" "$WORK"

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

say "Preparing the Termux build environment for $APP_PKG"
sudo mkdir -p "/data/data/$APP_PKG" && sudo chown -R "$(id -u):$(id -g)" /data
git clone --depth 1 https://github.com/termux/termux-packages.git "$WORK/tp"
cd "$WORK/tp"

grep -nE '^[[:space:]]*(export[[:space:]]+)?(TERMUX_APP__PACKAGE_NAME|TERMUX_APP_PACKAGE)=' scripts/properties.sh \
  || fail "scripts/properties.sh has no TERMUX_APP__PACKAGE_NAME / TERMUX_APP_PACKAGE line: termux-packages changed, the retarget step must be updated"
sed -i -E "s/^([[:space:]]*(export[[:space:]]+)?)(TERMUX_APP__PACKAGE_NAME|TERMUX_APP_PACKAGE)=.*/\1\3=\"$APP_PKG\"/" scripts/properties.sh
grep -E 'TERMUX_APP__PACKAGE_NAME=|TERMUX_APP_PACKAGE=' scripts/properties.sh

./scripts/setup-ubuntu.sh
./scripts/setup-android-sdk.sh

build() { say "Building: $*"; ./build-package.sh -a "$ARCH" "$@"; }   # builds the dependencies from source too (no -I: downloaded ones carry the com.termux prefix)

usr_dir()  { echo "$1$PREFIX_ABS"; }
stage()    { local dest="$1"; shift; mkdir -p "$dest"; for d in "$@"; do dpkg-deb -x "$d" "$dest"; done; }
files_of() { ( cd "$1" && find . \( -type f -o -type l \) | sort ); }
only_new() { # $1 = usr dir, $2 = output tar.gz : everything in $1 that the base package does not already contain
  files_of "$1" > "$WORK/all.txt"
  if [ -n "$BASE_LIST" ] && [ -f "$BASE_LIST" ]; then comm -23 "$WORK/all.txt" <(sort "$BASE_LIST") > "$WORK/new.txt"
  else echo "WARNING: no base file list, packing everything" >&2; cp "$WORK/all.txt" "$WORK/new.txt"; fi
  [ -s "$WORK/new.txt" ] || fail "nothing to pack for $2"
  tar -C "$1" -czf "$2" -T "$WORK/new.txt"
}

case "$GROUP" in
base)
  build bash dash coreutils findutils grep sed gawk tar gzip unzip zip diffutils patch which curl git ca-certificates termux-exec termux-tools termux-core
  S="$WORK/stage-base"; stage "$S" output/*.deb
  U="$(usr_dir "$S")"
  [ -x "$U/bin/bash" ] || fail "bash missing in the staged prefix"
  grep -aq "$PREFIX_ABS" "$U/bin/bash" || fail "bash does not contain $PREFIX_ABS: the prefix was NOT retargeted (it would be refused by the app)"
  files_of "$U" > "$OUT/base-files.txt"
  tar -C "$U" -czf "$OUT/base.tar.gz" .
  ;;
jdk)
  build openjdk-17 gradle
  G="$(ls output/gradle_*.deb | head -n1)"
  S="$WORK/stage-jdk"; stage "$S" $(ls output/*.deb | grep -v '/gradle_')
  only_new "$(usr_dir "$S")" "$OUT/jdk.tar.gz"
  SG="$WORK/stage-gradle"; stage "$SG" "$G"
  tar -C "$(usr_dir "$SG")" -czf "$OUT/gradle.tar.gz" .
  ;;
tools)
  AVAIL=(); for p in aapt aapt2 apksigner zipalign d8; do [ -d "packages/$p" ] && AVAIL+=("$p") || echo "no termux package named $p, skipped"; done
  [ "${#AVAIL[@]}" -gt 0 ] || fail "none of the Android tool packages exist in termux-packages"
  build "${AVAIL[@]}"
  S="$WORK/stage-tools"; stage "$S" output/*.deb
  only_new "$(usr_dir "$S")" "$OUT/tools.tar.gz"

  say "Assembling the Android SDK package (home-android-sdk)"
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
  SM="$SDK/cmdline-tools/latest/bin/sdkmanager"
  [ -x "$SM" ] || fail "sdkmanager not found in $SDK"
  yes | "$SM" --licenses >/dev/null || true
  "$SM" "platforms;android-34" "build-tools;34.0.0"
  H="$WORK/stage-home"; mkdir -p "$H/android-sdk/platforms" "$H/android-sdk/build-tools" "$H/.gradle"
  cp -a "$SDK/platforms/android-34" "$H/android-sdk/platforms/"
  cp -a "$SDK/licenses" "$H/android-sdk/"
  # build-tools: only the portable parts (jars + scripts). The CPU binaries (aapt2, zipalign) come from the aarch64 'tools' package.
  BT="$H/android-sdk/build-tools/34.0.0"; mkdir -p "$BT"
  cp -a "$SDK/build-tools/34.0.0/lib" "$SDK/build-tools/34.0.0/source.properties" "$BT/"
  for f in d8 apksigner; do [ -f "$SDK/build-tools/34.0.0/$f" ] && cp -a "$SDK/build-tools/34.0.0/$f" "$BT/"; done
  printf 'android.aapt2FromMavenOverride=%s/bin/aapt2\norg.gradle.daemon=false\n' "$PREFIX_ABS" > "$H/.gradle/gradle.properties"
  tar -C "$H" -czf "$OUT/home-android-sdk.tar.gz" .
  ;;
*) fail "unknown group $GROUP" ;;
esac

say "Done"
cd "$OUT" && ls -l && sha256sum *.tar.gz
