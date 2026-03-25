# Vendor Integration

This project integrates external HDR engines as pinned vendor dependencies.

## Layout

```text
Vendor/
├─ Sources/
│  ├─ toGainMapHDR/
│  └─ libultrahdr/
├─ Builds/
│  ├─ toGainMapHDR/
│  └─ libultrahdr/
└─ Manifest/
   └─ vendor-versions.json
```

`toGainMapHDR` is consumed as an embedded CLI tool.

`libultrahdr` is consumed through a local wrapper executable named `ultrahdr_bridge`.

## Update Workflow

1. Update the pinned ref in `Vendor/Manifest/vendor-versions.json`.
2. Run `Tools/update-togainmaphdr.sh` or `Tools/update-libultrahdr.sh`.
3. Rebuild the app and run sample conversions.
4. Commit the vendor manifest and integration changes together.
