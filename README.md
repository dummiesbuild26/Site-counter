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

Download the latest build from the repo's **Releases** page. Every push to the
default branch builds the app and publishes a new release (`v1.0.<run number>`)
with `SiteCounter.zip` attached. Pushing a `v*` tag publishes a release with
that version instead. (Because it's ad-hoc signed, right-click → **Open**
the first time.)

## iPhone & iPad

Each release also includes `SiteCounter.ipa`, an iOS 16+ version of the app
with the same stats, domain picker and pull-to-refresh.

The `.ipa` is unsigned, because installing on a device needs an Apple signing
identity. Install it with a sideloading tool that signs it with your Apple ID:

- **[Sideloadly](https://sideloadly.io)** (Mac/Windows): plug in your iPhone,
  drag `SiteCounter.ipa` in, enter your Apple ID, click **Start**.
- **[AltStore](https://altstore.io)**: install AltStore, then open the `.ipa`
  from the Files app with AltStore.

Then on the iPhone, go to **Settings → General → VPN & Device Management**, tap
your Apple ID and **Trust** it. On iOS 16+, also turn on **Settings → Privacy &
Security → Developer Mode**. With a free Apple ID the app has to be re-signed
every 7 days (AltStore can do this automatically).

To build it yourself: `brew install xcodegen && ./scripts/build-ipa.sh`, or run
`xcodegen generate`, open `SiteCounter.xcodeproj` in Xcode, pick your team under
Signing, and run it on your iPhone.

## Connecting to Cloudflare

1. Go to <https://dash.cloudflare.com/profile/api-tokens> → **Create Token** →
   **Create Custom Token** with these permissions:
   - **Zone → Zone → Read** (required, lists your domains)
   - **Zone → Analytics → Read** (required)
   - **Account → Account Settings → Read** (optional, shows your account name)
   - Zone Resources: **All zones** (or include each domain you want to see).
2. Open Site Counter → **Settings** (⌘, or the gear button) and enter:
   - **API Token** – stored in your macOS Keychain
   - **Account ID** (optional) – limits the domain list to one account. It's on
     any domain's **Overview** page in the Cloudflare dashboard (right-hand
     sidebar, "API" section).
3. Click **Save & Connect**.

All domains the token can see are found automatically. Use the domain menu in
the toolbar to switch between them, or pick **All Domains** to add them together.

Stats refresh automatically every 5 minutes, or press ⌘R.

## How it works

- Traffic data comes from Cloudflare's GraphQL Analytics API
  (`httpRequests1hGroups` for the 24-hour view, `httpRequests1dGroups` for
  7 / 30 days).
- Zone and account names come from the REST API (`/zones/{id}`,
  `/accounts/{id}`).
- "Unique visitors" for multi-day ranges is the sum of daily uniques, since
  Cloudflare doesn't de-duplicate visitors across days.
