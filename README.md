# Site Counter

A native macOS app (SwiftUI) that shows your website's Cloudflare analytics:
requests, page views, unique visitors, bandwidth, cache ratio, threats blocked,
a traffic chart and top countries. It also lives in the menu bar.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ or the Swift 5.9+ command-line tools (`xcode-select --install`)

## Build & run

```bash
# Quick run from the terminal
swift run

# Or build a double-clickable app into ./build
./scripts/build-app.sh
open "build/Site Counter.app"
```

You can also open `Package.swift` in Xcode and press ⌘R.

Download the latest build from the repo's **Releases** page. To publish a new
release, push a version tag (e.g. `git tag v1.1.0 && git push origin v1.1.0`);
GitHub Actions builds the app and attaches `SiteCounter.zip` to the release. (Because it's ad-hoc signed, right-click → **Open**
the first time.)

## Connecting to Cloudflare

1. Go to <https://dash.cloudflare.com/profile/api-tokens> → **Create Token** →
   **Create Custom Token** with these permissions:
   - **Zone → Analytics → Read** (required)
   - **Account → Account Settings → Read** (optional, shows your account name)
   - Zone Resources: include your zone (or all zones).
2. Open Site Counter → **Settings** (⌘, or the gear button) and enter:
   - **API Token** – stored in your macOS Keychain
   - **Zone ID** and **Account ID** – found on your domain's **Overview** page
     in the Cloudflare dashboard (right-hand sidebar, "API" section).
3. Click **Save & Connect**.

Stats refresh automatically every 5 minutes, or press ⌘R.

## How it works

- Traffic data comes from Cloudflare's GraphQL Analytics API
  (`httpRequests1hGroups` for the 24-hour view, `httpRequests1dGroups` for
  7 / 30 days).
- Zone and account names come from the REST API (`/zones/{id}`,
  `/accounts/{id}`).
- "Unique visitors" for multi-day ranges is the sum of daily uniques, since
  Cloudflare doesn't de-duplicate visitors across days.
