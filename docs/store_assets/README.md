# Store Assets Generated

All assets are in `docs/store_assets/`.

## iOS App Store

### 6.7" (iPhone 15 Pro Max) - Primary
| File | Description |
|------|-------------|
| `ios_67_home.png` | Your AI Workspace - project management |
| `ios_67_chat.png` | Intelligent Chat - codebase conversations |
| `ios_67_files.png` | Browse & Edit Files - syntax highlighting |
| `ios_67_terminal.png` | Powerful Tools - terminal, models, agents |

**Dimensions:** 1290 x 2796 px

### 6.5" (iPhone XS Max)
| File | Description |
|------|-------------|
| `ios_65_home.png` | Your AI Workspace |
| `ios_65_chat.png` | Intelligent Chat |
| `ios_65_files.png` | Browse & Edit Files |
| `ios_65_terminal.png` | Powerful Tools |

**Dimensions:** 1242 x 2688 px

### 5.5" (iPhone 8 Plus)
| File | Description |
|------|-------------|
| `ios_55_home.png` | Your AI Workspace |
| `ios_55_chat.png` | Intelligent Chat |
| `ios_55_files.png` | Browse & Edit Files |
| `ios_55_terminal.png` | Powerful Tools |

**Dimensions:** 1242 x 2208 px

## Google Play Store

### Feature Graphic
| File | Description |
|------|-------------|
| `android_feature.png` | Standard quality - 3 screenshots |
| `android_feature_hq.png` | High quality - 3 screenshots |

**Dimensions:** 1920 x 1080 px (standard) / 2560 x 1440 px (high quality)

## Usage

1. **iOS App Store Connect:**
   - Upload all 12 images (4 per device size)
   - Apple will automatically select the correct size for each device

2. **Google Play Console:**
   - Upload `android_feature_hq.png` as the Feature Graphic
   - Upload individual screenshots separately (crop from your raw screenshots if needed)

## Regenerating

To regenerate all assets:

```bash
python3 tools/generate_store_assets.py
```
