# Deployment Automation: Codemagic CI/CD

## Objective
Set up automated building, signing, and publishing of the Spark Flutter app to Apple App Store and Google Play Store using Codemagic.

## Prerequisites (User has confirmed)
- Apple Developer account ($99/yr) — active
- Google Play account ($25 one-time) — active
- Bundle ID: `zm.co.cloud.spark`
- GitHub repo: `arthurkay/spark`

## Setup Overview

### Phase 1: Signing Credentials (Manual — User does this)

#### iOS (Apple)
1. **App Store Connect API Key**
   - Go to https://appstoreconnect.apple.com/access/api
   - Click "Generate API Key" → Select "Full Access"
   - Download the `.p8` file (one-time download)
   - Note: Key ID, Issuer ID

2. **Distribution Certificate**
   - Go to https://developer.apple.com/account/resources/certificates/list
   - Create "iOS Distribution" certificate
   - Download `.cer` file
   - Export as `.p12` with password

3. **Provisioning Profile**
   - Go to https://developer.apple.com/account/resources/profiles/list
   - Create "App Store" provisioning profile for `zm.co.cloud.spark`
   - Download `.mobileprovision` file

#### Android (Google Play)
1. **Upload Keystore**
   - Generate keystore: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   - Store `upload-keystore.jks` securely (NOT in repo)

2. **Play Console Service Account**
   - Go to https://console.cloud.google.com
   - Create project → Enable "Google Play Android Developer API"
   - Create Service Account → Generate JSON key
   - Go to Play Console → Users and permissions → Invite service account
   - Grant "Release app to production" permission

### Phase 2: Codemagic Setup

#### 2.1 Connect Repository
1. Sign up at https://codemagic.io (free tier: 500 min/month)
2. Connect GitHub repository `arthurkay/spark`
3. Codemagic auto-detects Flutter project

#### 2.2 Upload Signing Credentials
1. **iOS Signing**
   - Go to Teams → Codemagic.yaml settings → Code signing identities
   - Upload: iOS certificates (`.p12` + password)
   - Upload: iOS provisioning profiles (`.mobileprovision`)

2. **Android Signing**
   - Go to Teams → Codemagic.yaml settings → Android signing
   - Upload: Keystore file (`.jks`)
   - Enter: Keystore password, Key alias, Key password

3. **App Store Connect Integration**
   - Go to Teams → Integrations → Developer Portal
   - Add App Store Connect API key (`.p8` file, Key ID, Issuer ID)

#### 2.3 Create codemagic.yaml
Create `codemagic.yaml` in repo root with workflows:

```yaml
workflows:
  # PR checks — fast, no signing
  pr-checks:
    name: PR Checks
    max_build_duration: 30
    instance_type: linux
    environment:
      flutter: stable
    scripts:
      - name: Install dependencies
        script: flutter pub get
      - name: Analyze
        script: flutter analyze
      - name: Run tests
        script: flutter test
    triggering:
      events:
        - pull_request

  # iOS release — signed, published to App Store
  ios-release:
    name: iOS Release
    max_build_duration: 60
    instance_type: mac_mini_m2
    integrations:
      app_store_connect: App Store Connect API key
    environment:
      flutter: stable
      ios_signing:
        distribution_type: app_store
        bundle_identifier: zm.co.cloud.spark
    scripts:
      - name: Install dependencies
        script: flutter pub get
      - name: Build iOS
        script: flutter build ipa --release --build-name=$VERSION_NAME --build-number=$VERSION_NUMBER
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        auth: integration
        submit_to_app_store: true
    triggering:
      events:
        - tag
      branch_patterns:
        - pattern: 'v*'
          include: true

  # Android release — signed, published to Play Store
  android-release:
    name: Android Release
    max_build_duration: 60
    instance_type: linux
    environment:
      flutter: stable
      android_signing:
        - keystore_reference
    scripts:
      - name: Install dependencies
        script: flutter pub get
      - name: Build Android
        script: flutter build appbundle --release --build-name=$VERSION_NAME --build-number=$VERSION_NUMBER
    artifacts:
      - build/**/outputs/**/*.aab
    publishing:
      google_play:
        credentials: $GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS
        track: production
    triggering:
      events:
        - tag
      branch_patterns:
        - pattern: 'v*'
          include: true
```

#### 2.4 Set Environment Variables
In Codemagic → Variables and secrets:
- `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` — JSON content from service account

### Phase 3: App Store Metadata (Manual)

#### Apple App Store Connect
1. Go to https://appstoreconnect.apple.com
2. Create new app: "Spark", Bundle ID: `zm.co.cloud.spark`
3. Add screenshots (required sizes for iPhone)
4. Add description, keywords, privacy URL
5. Set pricing (Free)
6. Complete app review information

#### Google Play Console
1. Go to https://play.google.com/console
2. Create new app: "Spark", Package: `zm.co.cloud.spark`
3. Add screenshots (phone, tablet)
4. Add description, full description
5. Set content rating
6. Set pricing (Free)
7. Complete store listing

## Workflow Summary

```
Developer pushes tag v1.0.0
        │
        ├─► iOS Release workflow
        │   ├─ Build signed IPA
        │   ├─ Upload to App Store Connect
        │   └─ Submit for review
        │
        └─► Android Release workflow
            ├─ Build signed AAB
            ├─ Upload to Play Console
            └─ Submit to production track
```

## Version Management
- Use git tags for releases: `v1.0.0`, `v1.0.1`, etc.
- Codemagic auto-increments build numbers
- Or set manually: `--build-name=1.0.0 --build-number=1`

## Files to Create/Modify
- `codemagic.yaml` — NEW: CI/CD workflow configuration
- `android/app/build.gradle` — May need signing config updates
- `pubspec.yaml` — Version number management

## Cost Estimate
- **Codemagic free tier**: 500 build minutes/month
- **Typical build**: ~5-10 minutes per platform
- **Monthly cost for 2 releases**: ~20-40 minutes (well within free tier)

## Success Criteria
- [ ] iOS builds signed and uploaded to App Store Connect
- [ ] Android builds signed and uploaded to Play Console
- [ ] Tag-based triggering works (push `v*` tag → builds)
- [ ] Build artifacts available for download
- [ ] Store listings created and ready for review
