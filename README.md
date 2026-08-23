# RCF

Native iOS (Swift/SwiftUI) manager for Cloudflare.
iOS 17+, iPhone-first, iPad-adaptive, zero external package dependencies.
Dark-ink design system (Light/Dark themes), zone-workspace shell, ⌘K command palette.

## Workflow

The Xcode project is **generated** — do not edit `RCF.xcodeproj` by hand.

```bash
# Regenerate the project after adding/removing files
xcodegen generate

# Build + run unit tests on the simulator
./scripts/build.sh
```

Open `RCF.xcodeproj` in Xcode for manual runs (scheme: `RCF`,
destination: iPhone 17 Pro simulator).

## Layout

- `RCF/App` — entry point, root gate, tab bar
- `RCF/Core` — networking, security (Keychain), models, persistence, shared UI
- `RCF/Features` — feature folders (Zones, DNS, Workers, …)
- `RCFTests` — unit tests
- `docs/` — [architecture decisions](docs/architecture.md), [Cloudflare API quirks ledger](docs/cloudflare-api-quirks.md)
- `plans/` — implementation plan + phase docs

API tokens live only in the Keychain; nothing sensitive touches UserDefaults or logs.
