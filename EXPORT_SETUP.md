# Android export setup — machine-specific notes

This project exports headlessly via the Godot CLI (`godot --headless --export-debug/--export-release`),
no editor GUI involved. Getting this working on a fresh machine — through both a debug
build and a fully signed release `.aab` — hit a real string of gotchas, documented here
so they don't need re-discovering.

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

## Stray `.import` files break the Gradle resource merge

`android/build` sits inside the Godot project tree (`res://android/build/...`), so
Godot's own filesystem scanner picks up the icon `.webp` files it generates there and
creates `.import` sidecar metadata files right next to them
(`icon_foreground.webp.import` etc). Android's resource merger then chokes on these —
`mergeStandardReleaseResources` fails with *"The file name must end with .xml or
.png"*. **Fix: add an empty `android/.gdignore` file** so Godot never scans that tree as
project resources in the first place:
```bash
touch android/.gdignore
```
This needs to be re-created any time `android/` is deleted and re-extracted (it's
gitignored along with the rest of `android/`).

## export_presets.cfg gotchas

- `gradle_build/min_sdk` must be `>= 24` for Godot 4.7 (`21` fails with an explicit error).
- `gradle_build/use_gradle_build=true` is required — Godot 4.x has no non-Gradle Android
  export path (that was a Godot 3.x feature), and `.aab` output specifically requires it.
- Leave `gradle_build/gradle_build_directory=""` (empty) unless you have a reason to
  override it — setting it explicitly changes template-detection behavior in ways that
  reintroduced the "template not installed" error during troubleshooting.
- **`gradle_build/export_format=1` is required for `.aab` output** — it defaults to `0`
  (APK) if omitted, which fails with *"Invalid filename! Android APK requires the *.apk
  extension"* the moment you pass a `.aab` output path.
- **`export_filter="all_resources"` bundles EVERYTHING in the project into the shipped
  build unless excluded** — including the release keystore if it lives in the project
  root. Set `exclude_filter` to keep secrets and dev-only files out of the actual APK/AAB:
  ```
  exclude_filter="*.jks,keystore.properties,*.md,export_presets.cfg.example,EXPORT_SETUP.md,scripts_gen/*,scripts/tests/*,levels/LEVEL_DESIGN_NOTES.md"
  ```
  Verify after every release build: `unzip -l build/*.aab | grep -iE "\.jks|keystore"` should
  print nothing.
- **`export_presets.cfg` itself is gitignored, not committed** — once it holds real
  `keystore/release_password` values it's a secrets file, same as `keystore.properties`.
  A blank-credentials `export_presets.cfg.example` is committed instead as the
  reproducible template; copy it to `export_presets.cfg` and fill in real values locally.

## Once all of the above is done

```bash
godot --headless --export-debug "Android" build/some-name.apk    # sanity check
godot --headless --export-release "Android" build/GemCascade-v1.0.0.aab  # the real deliverable
```

Verify the result:
```bash
unzip -t build/GemCascade-v1.0.0.aab           # zip integrity
jarsigner -verify -verbose build/GemCascade-v1.0.0.aab   # should say "jar verified"
unzip -l build/GemCascade-v1.0.0.aab | grep -iE "\.jks|keystore"   # should be empty
```
