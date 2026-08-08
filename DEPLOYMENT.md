# Deployment Guide — Spark App

How to publish **Spark** to the Apple App Store and Google Play Store using Codemagic CI/CD.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [One-Time Setup](#one-time-setup)
   - [2.1 Android — Keystore](#21-android--keystore)
   - [2.2 Android — Google Play Service Account](#22-android--google-play-service-account)
   - [2.3 iOS — App Store Connect API Key](#23-ios--app-store-connect-api-key)
   - [2.4 iOS — Distribution Certificate](#24-ios--distribution-certificate)
   - [2.5 iOS — Provisioning Profile](#25-ios--provisioning-profile)
3. [Codemagic Setup](#codemagic-setup)
   - [3.1 Connect Repository](#31-connect-repository)
   - [3.2 Store Secrets](#32-store-secrets)
   - [3.3 Code Signing](#33-code-signing)
4. [Build & Publish](#build--publish)
   - [4.1 Trigger a Build](#41-trigger-a-build)
   - [4.2 Manual Build](#42-manual-build)
5. [Version Management](#version-management)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Android | iOS |
|-------------|---------|-----|
| Developer account | Google Play Console ($25 one-time) | Apple Developer Program ($99/yr) |
| App listed in store | Yes | Yes |
| Bundle ID | `zm.co.cloud.spark` | `zm.co.cloud.spark` |
| Codemagic account | [codemagic.io](https://codemagic.io) | Same |

---

## One-Time Setup

### 2.1 Android — Keystore

Generate a release keystore (run once, keep it safe):

```bash
keytool -genkey -v \
  -keystore ~/spark-release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias spark
```

You will be prompted for:
- **Keystore password** — pick something strong, you'll need it in Codemagic
- **Key password** — can be the same as the keystore password

Base64-encode the keystore for Codemagic:

```bash
base64 -i ~/spark-release.jks | tr -d '\n' | pbcopy
```

This copies the base64 string to your clipboard. Paste it into Codemagic later as `KEYSTORE_BASE64`.

> **NEVER** commit the `.jks` file or its passwords to git.

### 2.2 Android — Google Play Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project (or use existing)
3. Enable the **Google Play Android Developer API**
4. Go to **IAM & Admin → Service Accounts → Create Service Account**
5. Name it (e.g. `codemagic-deploy`)
6. Go to **Keys → Add Key → Create new key → JSON**
7. Download the JSON file
8. Go to [Play Console](https://play.google.com/console) → **Setup → API access**
9. Invite the service account email as a **Release manager**
10. Accept the invitation

Store the entire JSON file contents in Codemagic as `PLAY_SERVICE_ACCOUNT_JSON`.

### 2.3 iOS — App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/access/api)
2. Click **Generate API Key** → Select **Full Access**
3. Name it (e.g. `Codemagic`)
4. Download the `.p8` file (you can only download it once)
5. Note the **Key ID** and **Issuer ID**

Store in Codemagic:
- `APPLE_API_KEY` — contents of the `.p8` file
- `APPLE_API_KEY_ID` — the Key ID
- `APPLE_API_ISSUER_ID` — the Issuer ID

### 2.4 iOS — Distribution Certificate

1. Go to [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click **+** → Create **iOS Distribution** certificate
3. Upload a CSR (Certificate Signing Request) — generate one in **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**
4. Download the `.cer` file
5. Double-click to install in Keychain
6. In **Keychain Access**, find the certificate, right-click → **Export**
7. Export as `.p12` with a password

> **Alternative**: Codemagic can generate and manage certificates for you automatically. See [Codemagic iOS signing docs](https://docs.codemagic.io/ios-code-signing/ios-code-signing/).

### 2.5 iOS — Provisioning Profile

1. Go to [Apple Developer Profiles](https://developer.apple.com/account/resources/profiles/list)
2. Click **+** → Create **App Store** provisioning profile
3. Select your App ID (`zm.co.cloud.spark`)
4. Select your distribution certificate
5. Download the `.mobileprovision` file

> **Alternative**: If using automatic signing in Codemagic, this is handled automatically.

---

## Codemagic Setup

### 3.1 Connect Repository

1. Sign in to [codemagic.io](https://codemagic.io)
2. Click **Add application** → Select **GitHub**
3. Authorize Codemagic
4. Select your `spark` repository
5. Codemagic auto-detects the Flutter project

### 3.2 Store Secrets

Go to **Teams → Variables and secrets** and add:

| Variable | Value | Protected | Group |
|----------|-------|-----------|-------|
| `KEYSTORE_BASE64` | base64 of `spark-release.jks` | Yes | `android` |
| `KEYSTORE_PASSWORD` | Keystore password | Yes | `android` |
| `KEY_PASSWORD` | Key alias password | Yes | `android` |
| `KEY_ALIAS` | `spark` | No | `android` |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google service account JSON | Yes | `android` |
| `APPLE_API_KEY` | `.p8` file contents | Yes | `ios` |
| `APPLE_API_KEY_ID` | Key ID | No | `ios` |
| `APPLE_API_ISSUER_ID` | Issuer ID | No | `ios` |

### 3.3 Code Signing

#### Android

1. Go to **Teams → Codemagic.yaml settings → Android signing**
2. Upload `spark-release.jks`
3. Enter:
   - **Keystore password**: your keystore password
   - **Key alias**: `spark`
   - **Key password**: your key password
4. Codemagic generates a reference name — note it for `codemagic.yaml`

#### iOS

**Option A: Manual signing**

1. Go to **Teams → Codemagic.yaml settings → Code signing identities**
2. Upload your `.p12` certificate + password
3. Upload your `.mobileprovision` profile

**Option B: Automatic signing (recommended)**

Codemagic can manage certificates and profiles automatically:
1. Go to **Teams → Integrations → Developer Portal**
2. Add your App Store Connect API key
3. Codemagic handles certificate + profile creation

---

## Build & Publish

### 4.1 Trigger a Build

Push a version tag to trigger release builds:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers both iOS and Android workflows.

### 4.2 Manual Build

In Codemagic UI:
1. Select your app
2. Click **Start new build**
3. Select workflow (`ios-release` or `android-release`)
4. Select branch and tag
5. Click **Start build**

### 4.3 Build Output

| Platform | Artifact | Uploaded to |
|----------|----------|-------------|
| Android | `.aab` (App Bundle) | Play Console → Production track |
| iOS | `.ipa` | App Store Connect → TestFlight |

After upload:
- **Android**: Review in Play Console → Submit to production
- **iOS**: Review in TestFlight → Submit for App Store review

---

## Version Management

Versions are controlled in `pubspec.yaml`:

```yaml
version: 1.0.0+1
#          │     │
#          │     └─ Build number (iOS buildNumber, Android versionCode)
#          └─────── Version name (iOS marketing version, Android versionName)
```

**Release workflow:**

1. Update version in `pubspec.yaml`:
   ```yaml
   version: 1.1.0+2
   ```
2. Commit and push:
   ```bash
   git add pubspec.yaml
   git commit -m "Bump version to 1.1.0"
   git push origin main
   ```
3. Create and push tag:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```

Codemagic uses the version from `pubspec.yaml` for both platforms.

---

## Troubleshooting

### Android build fails

| Error | Fix |
|-------|-----|
| `Keystore was tampered with` | Verify `KEYSTORE_PASSWORD` is correct |
| `No key with alias 'spark'` | Verify `KEY_ALIAS` matches the alias used during keytool generation |
| `Google Play service account not found` | Check `PLAY_SERVICE_ACCOUNT_JSON` contains valid JSON |
| `App not found in Play Console` | Ensure app with package `zm.co.cloud.spark` exists and service account has access |

### iOS build fails

| Error | Fix |
|-------|-----|
| `No signing certificate` | Upload distribution certificate or enable automatic signing |
| `Provisioning profile not found` | Upload `.mobileprovision` or use automatic signing |
| `Invalid API key` | Verify `APPLE_API_KEY`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` |
| `Bundle identifier mismatch` | Ensure Bundle ID `zm.co.cloud.spark` is registered in Apple Developer portal |

### General

- **Build timeout**: Increase `max_build_duration` in `codemagic.yaml`
- **Dependencies fail**: Check `flutter pub get` works locally
- **Tests fail**: Fix tests locally before pushing

---

## Files Reference

| File | Purpose |
|------|---------|
| `codemagic.yaml` | CI/CD workflow configuration |
| `android/app/build.gradle.kts` | Android build config with signing |
| `pubspec.yaml` | Version number (source of truth) |
| `ios/Runner.xcodeproj/project.pbxproj` | iOS project config |
