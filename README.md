# AppSizeGuard

Build-time iOS app size analyzer. Runs as a macOS CLI during an Xcode Run Script phase and reports issues in the Issue Navigator. Nothing is embedded in the app binary.

---

## Requirements

- macOS 13+
- Swift 5
- Xcode project with `project.pbxproj`

See [AppSizeRequirements.txt](AppSizeRequirements.txt) for the full specification.

---

## Scanners

| Scanner | When | Notes |
|---------|------|-------|
| Oversized assets | Debug & Release | Source files in active target only; `.car` out of scope |
| Duplicate assets | Debug & Release | SHA256 content hash; ignores @2x/@3x naming |
| Unused resources | Debug & Release | Conservative; notes on dynamic references |
| Dependencies | Debug | CocoaPods + SPM size reporting only |
| Bundle growth | **Debug only** | Compare vs committed baseline |

---

## Step 1 — Build the Tool

```bash
swift build -c release --package-path /Users/yourname/AppSizeGuard
```
---

## Step 2 — Copy the Binary to Your iOS Project

```bash
cp /Users/yourname/AppSizeGuard/.build/release/appsizeguard \
   /Users/yourname/YourIOSProject/appsizeguard
```

**To rebuild from scratch (clean build):**

```bash
rm -rf /Users/yourname/AppSizeGuard/.build \
  && swift build -c release --package-path /Users/yourname/AppSizeGuard \
  && cp /Users/yourname/AppSizeGuard/.build/release/appsizeguard \
        /Users/yourname/YourIOSProject/appsizeguard
```

---

## Step 3 — Update `.gitignore`

Open your iOS project's `.gitignore` and add:

```
appsizeguard
.appsizeguard-baseline.json
```

---

## Step 4 — Create `.appsizeguard.yml`

Run this command in your terminal (adjust the path to your project root):

Terminal
cat > /Users/yourname/YourIOSProject/.appsizeguard.yml << 'EOF'
is_production: true
EOF

or for giving thresholds

cat > /Users/joshnagoud.n/Documents/SourceTree_Fork/myIM3Swift_Fork/.appsizeguard.yml << 'EOF'
is_production: true      # set to false for staging builds

thresholds:
  png:
    warn_kb: 500
    error_kb: 1024
  jpg:
    warn_kb: 500
    error_kb: 1024
  gif:
    warn_kb: 500
    error_kb: 1024
  json:
    warn_kb: 500
    error_kb: 1024
  mp4:
    warn_kb: 500
    error_kb: 1024
  ttf:
    warn_kb: 500
    error_kb: 1024
  pdf:
    warn_kb: 500
    error_kb: 1024

growth:
  warn_percent: 5
  error_percent: 15

dependencies:
  warn_size_mb: 10
EOF

Or create the file manually at `/Users/yourname/YourIOSProject/.appsizeguard.yml`:
is_production: true      # set to false for staging builds


See [.appsizeguard.yml.example](.appsizeguard.yml.example) for all available options.

---

## Step 5 — Add Run Script Phase in Xcode

1. Open your iOS project in Xcode.
2. Go to your **Target → Build Phases**.
3. Click **+** → **New Run Script Phase**.
4. Drag it to the bottom, **after Copy Bundle Resources**.
5. Paste this script:

```bash
"${SRCROOT}/appsizeguard" \
  --project-dir "${PROJECT_DIR}" \
  --target "${TARGET_NAME}" \
  --configuration "${CONFIGURATION}" \
  --built-products-dir "${BUILT_PRODUCTS_DIR}" \
  --product-name "${FULL_PRODUCT_NAME}" \
  --srcroot "${SRCROOT}"
```

---

## Baseline Policy

| Context | Behaviour |
|---------|-----------|
| Local Debug builds | **Compare only** — reads `.appsizeguard-baseline.json` |
| CI | Set `APPSIZEGUARD_UPDATE_BASELINE=1` to overwrite the baseline after each Debug scan |

Commit baseline updates from your pipeline (auto-commit or PR step).

---

## Xcode Output Format

```
/path/to/file.png:1:1: warning: [AppSizeGuard/Assets] message
```

> Errors are shown for visibility but **the build never fails** (exit code 0).

---

## Testing the Binary Manually

You can run the binary directly from your terminal to verify it works before triggering a build:

```bash
/Users/yourname/YourIOSProject/appsizeguard \
  --project-dir "/Users/yourname/YourIOSProject" \
  --target "YourTargetName" \
  --configuration "Debug" \
  --built-products-dir "/Users/yourname/Library/Developer/Xcode/DerivedData/YourProject-xxxx/Build/Products/Debug-iphoneos" \
  --product-name "YourApp.app" \
  --srcroot "/Users/yourname/YourIOSProject" 2>&1
```

---
## App Size Report

```bash
APPSIZEGUARD_UPDATE_BASELINE=1 \
/Users/yourname/YourIOSProject/appsizeguard \
  --project-dir "/Users/yourname/YourIOSProject" \
  --target "YourTargetName" \
  --configuration "Debug" \
  --built-products-dir "/Users/yourname/Library/Developer/Xcode/DerivedData/YourProject-xxxx/Build/Products/Debug-iphoneos" \
  --product-name "YourApp.app" \
  --srcroot "/Users/yourname/YourIOSProject" 2>&1
```

## Quick Reference — Common Commands

| Task | Command |
|------|---------|
| Build tool | `swift build -c release --package-path /path/to/AppSizeGuard` |
| Copy binary | `cp AppSizeGuard/.build/release/appsizeguard /path/to/YourProject/appsizeguard` |
| Rebuild & copy (one-liner) | `rm -rf AppSizeGuard/.build && swift build -c release --package-path AppSizeGuard && cp AppSizeGuard/.build/release/appsizeguard YourProject/appsizeguard` |
| Create config | `echo "is_production: true" > /path/to/YourProject/.appsizeguard.yml` |
| Update baseline on CI | Set env var `APPSIZEGUARD_UPDATE_BASELINE=1` |



##Steps for Conveting Executable binary to SPM
 * Step 1: Build the release binary
    swift build -c release --package-path /Users/UsersName/Documents/RNDTask/NEWPOC/AppSizeGuard
    
 * Step 2: Create the artifact bundle folder structure
    mkdir -p /Users/UsersName/Documents/RNDTask/NEWPOC/appsizeguard.artifactbundle/appsizeguard-1.0.0-macos/bin
 * Step 3 — Copy the binary into the bundle
    cp /Users/joshnagoud.n/Documents/RNDTask/NEWPOC/AppSizeGuard/.build/release/appsizeguard \
   /Users/joshnagoud.n/Documents/RNDTask/NEWPOC/appsizeguard.artifactbundle/appsizeguard-1.0.0-macos/bin/appsizeguard
 *  Step 4 — Create the info.json manifest

   cat > /Users/joshnagoud.n/Documents/RNDTask/NEWPOC/appsizeguard.artifactbundle/info.json << 'EOF'
{
  "schemaVersion": "1.0",
  "artifacts": {
    "appsizeguard": {
      "version": "1.0.0",
      "type": "executable",
      "variants": [
        {
          "path": "appsizeguard-1.0.0-macos/bin/appsizeguard",
          "supportedTriples": [
            "arm64-apple-macosx",
            "x86_64-apple-macosx"
          ]
        }
      ]
    }
  }
}
EOF

 * Step 5 — Zip the artifact bundle
 cd /Users/joshnagoud.n/Documents/RNDTask/NEWPOC && \
zip -r appsizeguard.artifactbundle.zip appsizeguard.artifactbundle

 * Step 6 — Get the checksum
 swift package compute-checksum /Users/joshnagoud.n/Documents/RNDTask/NEWPOC/appsizeguard.artifactbundle.zip
 
 
 * Step 7 — Push to GitHub and create a release

    Create a new GitHub repo called AppSizeGuard
    Push your AppSizeGuard source code
    Go to GitHub → Releases → Create new release
    Tag it 1.0.0
    Upload appsizeguard.artifactbundle.zip as a release asset
    Copy the download URL of the zip file
    
 * Step 8 — Create Package.swift for the SPM package
 
 // swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSizeGuard",
    platforms: [.macOS(.v13)],
    products: [
        .plugin(name: "AppSizeGuardPlugin", targets: ["AppSizeGuardPlugin"])
    ],
    targets: [
        .binaryTarget(
            name: "AppSizeGuardBinary",
            url: "https://github.com/YOUR_USERNAME/AppSizeGuard/releases/download/1.0.0/appsizeguard.artifactbundle.zip",
            checksum: "PASTE_CHECKSUM_HERE"
        ),
        .plugin(
            name: "AppSizeGuardPlugin",
            capability: .buildTool(),
            dependencies: ["AppSizeGuardBinary"]
        )
    ]
)

 * Step 9 — How developers integrate it

Any iOS project adds this to their Package.swift or via Xcode → Add Package:
https://github.com/YOUR_USERNAME/AppSizeGuard





