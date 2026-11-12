# Brand assets

## Files

| File | Source |
|------|--------|
| `redhat-logo-on-dark.svg` | [Red Hat brand assets](https://static.redhat.com/libs/redhat/brand-assets/2/corp/logo--on-dark.svg) (reverse / on-dark) |
| `favicon.svg` | Official hat mark from [ux.redhat.com](https://ux.redhat.com/assets/logo-red-hat.svg) (same asset RHDS uses as site favicon) |
| `favicon-16.png`, `favicon-32.png`, `favicon.ico`, `apple-touch-icon.png` | Generated via `node scripts/generate-favicon.mjs` |
| `og-preview.png` | Open Graph / Twitter card image (**1200×630**). Generate with `node scripts/generate-og-preview.mjs` |

The cover composites the official Red Hat reverse logo and the official NVIDIA wordmark on a PatternFly dark canvas (`#151515`, bar `#ee0000`). Product names are text. Do not recreate or modify the logo artwork.

## Usage

- Favicon: official Red Hat hat.
- Share card: reverse Red Hat logo, NVIDIA wordmark, **hello-openshell** as the tool name, OpenShell 0.1.8 as the product line.
- Live `og:image` and `twitter:image` point at `og-preview.png` (PNG, not SVG). Social crawlers do not render SVG covers.
