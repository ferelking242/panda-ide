---
name: Official Marketplace assets
description: Constraints for using Microsoft’s Visual Studio Marketplace Gallery for extension metadata, content and VSIX downloads.
---

Use the Visual Studio Marketplace Gallery as the single source for extension search, metadata, README, changelog and VSIX assets. Gallery download URLs may use publisher-specific `*.gallerycdn.vsassets.io` or `*.gallery.vsassets.io` hosts rather than `marketplace.visualstudio.com`.

**Why:** Mixing Open VSX produces inconsistent metadata and content, while rejecting the Gallery CDN makes otherwise valid Microsoft VSIX installs fail.

**How to apply:** Keep the Gallery query flags aligned with the fields shown in the sidebar, resolve relative README links against the version `assetUri`, and allow only the official Gallery/CDN host patterns for downloads.

The current Gallery API requires the `Microsoft.VisualStudio.Code` product criterion for a non-empty featured query, and returns `resultMetadata` as a list of metadata groups rather than a single map.

**Why:** An empty criteria list currently returns no extensions, and casting the metadata list to a map crashes the Marketplace before the first result is displayed.

**How to apply:** Preserve the product criterion when building the initial query and extract `TotalCount` from `metadataItems`, while accepting older map-shaped responses for compatibility.