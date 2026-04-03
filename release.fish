#!/usr/bin/env fish

# Usage: ./release.fish [patch|minor|major]
# Default: patch (1.0.0 → 1.0.1)

set bump_type (test (count $argv) -gt 0; and echo $argv[1]; or echo patch)

# Read current version from manifest.json
set current (jq -r .version manifest.json)
set parts (string split '.' -- "$current")
set major $parts[1]
set minor $parts[2]
set patch $parts[3]

switch $bump_type
    case patch
        set patch (math $patch + 1)
    case minor
        set minor (math $minor + 1)
        set patch 0
    case major
        set major (math $major + 1)
        set minor 0
        set patch 0
    case '*'
        echo "Usage: release.fish [patch|minor|major]"
        exit 1
end

set new_version "$major.$minor.$patch"
echo "Bumping $current → $new_version"

# Update version in manifest.json and package.json
jq --arg v "$new_version" '.version = $v' manifest.json > manifest.tmp && mv manifest.tmp manifest.json
jq --arg v "$new_version" '.version = $v' package.json > package.tmp && mv package.tmp package.json

# Build
echo "Building..."
npm run build 2>&1
if test $status -ne 0
    echo "Build failed!"
    exit 1
end

# Commit, tag, push
git add manifest.json package.json main.js styles.css
git commit -m "Release $new_version"
git tag "$new_version"
git push origin main --tags

# Create GitHub release
echo "Creating release..."
gh release create "$new_version" main.js manifest.json styles.css \
    --title "$new_version" \
    --generate-notes

echo "Released $new_version"
