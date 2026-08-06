# Android export setup — machine-specific notes

This project exports headlessly via the Godot CLI (`godot --headless --export-debug/--export-release`),
no editor GUI involved. Getting this working on a fresh machine hit three real
gotchas, documented here so they don't need re-discovering.

## One-time machine setup

1. **Android SDK + JDK 17** — same toolchain as GlassRush (see that project's
   `EXPORT_SETUP.md`/`ARCHITECTURE.md` if present): `brew install --cask android-commandlinetools`,
   `brew install openjdk@17`, accept licenses, install `platform-tools` + a platform + build-tools.
2. **Godot 4.7 export templates**: `brew install --cask godot`, then download
   `Godot_v4.7.1-stable_export_templates.tpz` from the GitHub release and extract its
   `templates/` folder to `~/Library/Application Support/Godot/export_templates/4.7.1.stable/`.
3. **Point Godot's editor settings at the real SDK paths** — Godot's default
   `editor_settings-4.7.tres` ships with placeholder paths that don't exist
   (`~/Library/Android/sdk`). Edit `~/Library/Application Support/Godot/editor_settings-4.7.tres`:
   ```
   export/android/java_sdk_path = "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
   export/android/android_sdk_path = "/opt/homebrew/share/android-commandlinetools"
   ```
4. **Generate the debug keystore** Godot expects at
   `~/Library/Application Support/Godot/keystores/debug.keystore` (this is NOT created
   automatically in a headless environment — normally the editor GUI generates it on
   first run):
   ```bash
   keytool -genkeypair -v -keystore "$HOME/Library/Application Support/Godot/keystores/debug.keystore" \
     -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
     -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
   ```

## Installing the Android build template

`godot --headless --install-android-build-template` **hangs indefinitely** in a
sandboxed/headless shell (confirmed via `sample` — it spins in a `nanosleep` retry loop,
partly inside a macOS LaunchServices/`NSRunningApplication` call, which likely never
resolves without a real WindowServer session). Do NOT rely on this command.

**Do this instead** — extract the template manually and write the version marker by hand:

```bash
cd "<project>"
mkdir -p android/build
unzip -q "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/android_source.zip" -d android/build
chmod +x android/build/gradlew

# THE version file goes ONE LEVEL UP from build/, not inside it — this is the
# actual bug that cost the most time to find. Godot's own source
# (editor/export/export_template_manager.cpp, install_android_template_from_file):
#   build_dir = "res://android/build"
#   parent_dir = build_dir.get_base_dir()   # -> "res://android"  <-- .build_version goes HERE
#   f->store_line(GODOT_VERSION_FULL_CONFIG)  # content = "4.7.1.stable" + newline
echo "4.7.1.stable" > android/.build_version
```

Confirm the version string matches your installed Godot (`godot --version` starts with
it, e.g. `4.7.1.stable.official.a13da4feb` — you want the `4.7.1.stable` prefix, not the
git-hash suffix; both this and the git-hash-included variant were tried, only the
bare `X.Y.Z.status` form is correct).

## The ADB daemon has to be running

Godot's export step tries to talk to `adb` and errors/behaves oddly if the daemon isn't
up. It does NOT persist across separate shell invocations in some sandboxes — start it
in the **same command** as the export, or make sure it's actually still running:

```bash
/opt/homebrew/share/android-commandlinetools/platform-tools/adb start-server
```

## export_presets.cfg gotchas

- `gradle_build/min_sdk` must be `>= 24` for Godot 4.7 (`21` fails with an explicit error).
- `gradle_build/use_gradle_build=true` is required — Godot 4.x has no non-Gradle Android
  export path (that was a Godot 3.x feature), and `.aab` output specifically requires it.
- Leave `gradle_build/gradle_build_directory=""` (empty) unless you have a reason to
  override it — setting it explicitly changes template-detection behavior in ways that
  reintroduced the "template not installed" error during troubleshooting.

## Once all of the above is done

```bash
godot --headless --export-debug "Android" build/some-name.apk    # sanity check
godot --headless --export-release "Android" build/GemCascade.aab # the real deliverable, needs release signing configured
```
