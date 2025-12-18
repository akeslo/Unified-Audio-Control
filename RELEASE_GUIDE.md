# Creating a Release with Auto-Update Support

This guide shows how to create a new release that the built-in update system will detect and offer to users.

## Quick Steps

1. **Tag the version:**
   ```bash
   git tag v1.0.4  # Increment minor version
   git push origin v1.0.4
   ```

2. **Build with version from tag:**
   ```bash
   ./master_build.sh
   # Will automatically use v1.0.4 from git tag
   ```

3. **Package for distribution:**
   ```bash
   zip -r UnifiedAudioControl-v1.0.4.zip UnifiedAudioControl.app
   ```

4. **Create GitHub release:**
   - Go to: https://github.com/akeslo/Unified-Audio-Control/releases/new
   - Choose tag: `v1.0.4`
   - Title: `Version 1.0.4` or descriptive name
   - Description: Add release notes (shown to users in update dialog)
   - Attach: `UnifiedAudioControl-v1.0.4.zip`
   - **Publish** (not Draft)

5. **Done!** Users' apps will detect the new version automatically.

## Version Numbering

Follow semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (1.x.x → 2.0.0)
- **MINOR**: New features, non-breaking (1.2.x → 1.3.0)
- **PATCH**: Bug fixes (1.2.3 → 1.2.4)

> [!TIP]
> User preference is to increment **minor** version for most releases (e.g., 1.2 → 1.3)

## Release Notes Best Practices

Write release notes that will appear in the update dialog:

```markdown
## What's New

- Added support for external display volume control
- Fixed HUD display on secondary monitors
- Improved Bluetooth device name detection

## Bug Fixes

- Resolved issue with mute state persistence
- Fixed memory leak in audio device monitoring
```

Use clear, user-friendly language. These notes appear in the app's update dialog!

## Testing the Update Flow

After publishing a release:

1. **Temporarily downgrade** your local version in `master_build.sh`:
   ```bash
   VERSION="1.0.3"  # Or earlier than published release
   ```

2. **Rebuild** the app with older version number

3. **Launch** and open Preferences → Updates

4. **Click** "Check for Updates"

5. **Verify** the new release is detected and offered

6. **Restore** the VERSION in build script or let it auto-detect from git tags

## Troubleshooting

**Update not detected?**
- Ensure release is Published (not Draft)
- Verify release is not marked as Pre-release
- Check version tag format: `v1.0.4` or `1.0.4` (both work)
- Confirm `.zip` file is attached to the release

**Download fails?**
- Release must include a `.zip` file as an asset
- Asset name should end with `.zip`
- File must contain `UnifiedAudioControl.app` bundle

**Version comparison wrong?**
- Ensure tags follow semantic versioning
- Use dots between numbers: `1.0.4` not `1.04`
- Tags with `v` prefix work fine: `v1.0.4`
