# Beast runtime builder (GitHub Actions)

Builds the Linux runtime (bash, git, curl, JDK 17, Gradle, aapt2, Android SDK platform) for the app's own package name,
so Beast Mode can stream it from Google Drive. Nothing is added to the APK.

## One-time steps (all from the phone browser is fine)
1. github.com -> New repository (private is OK), e.g. `beast-runtime`.
2. Upload this folder's contents: `build-runtime.sh`, `README.md` and the `.github/workflows/build.yml` file (keep the path).
3. Repo -> Actions -> **Build Beast runtime** -> Run workflow. Wait (base first, then jdk + tools; expect 1-4 hours).
4. When it finishes: repo -> Releases -> latest `Beast runtime N`. Download:
   `base.tar.gz` (required), `jdk.tar.gz`, `gradle.tar.gz`, `tools.tar.gz`, `home-android-sdk.tar.gz`.
5. In GZ AI: Beast -> projects -> **Upload runtime...** -> pick the files (base first / together). Then use Beast.

## Notes
* If a job fails, open the failed step's log and send it; the upstream Termux build scripts change over time and this
  builder may need a small adjustment.
* The app must be built with targetSdk 28 (see app/build.gradle.kts), otherwise Android 10+ refuses to run the runtime.
* Free GitHub runners have limited disk/time: python, node and clang are not built here.
