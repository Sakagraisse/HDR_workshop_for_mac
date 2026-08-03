# ultrahdr_bridge

Objective-C++ bridge between Apple image frameworks and `libultrahdr`.

Build and package:

```text
Tools/build-ultrahdr-bridge.sh
Tools/package-vendors.sh
```

The executable accepts a versioned JSON request:

```text
ultrahdr_bridge --request /path/request.json
```

Supported operations:

- `inspect`
- `verify`
- `encodeHDR`
- `encodePair`
- `normalizeExisting`

Example:

```json
{
  "protocolVersion": 1,
  "operation": "encodePair",
  "hdrInput": "/tmp/master.tiff",
  "sdrInput": "/tmp/base.jpg",
  "output": "/tmp/out.jpg",
  "baseQuality": 95,
  "gainMapQuality": 95,
  "gainMapScale": 1,
  "multiChannel": true,
  "preset": "bestQuality",
  "colorGamut": "DisplayP3"
}
```
