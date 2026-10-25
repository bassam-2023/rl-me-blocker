# Releasing a new version

The app updates itself: it reads `latestVersion` from `ranges.json` on `main`, and when that is
newer it downloads `src/install.ps1` **from the matching tag** (`vX.Y.Z`). So the tag must exist
before `latestVersion` points at it.

1. Bump `$AppVersion` in `src/RL-ME-Blocker.ps1`, commit and push.
2. Build: `powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1`
3. Publish the release (this creates the tag):
   `gh release create vX.Y.Z dist/RL-ME-Blocker-vX.Y.Z.zip --target main --title "RL ME Blocker X.Y.Z" --notes "..."`
4. **Only then** set `"latestVersion": "X.Y.Z"` in `ranges.json`, commit and push. Installed apps
   will offer the update the next time they open (allow a few minutes for GitHub's cache).

Changing only the server ranges needs no release: edit `ranges.json` on `main` and every app picks it up.
