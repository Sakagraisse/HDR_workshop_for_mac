# ultrahdr_bridge

Input:

```text
ultrahdr_bridge --request /path/request.json
```

Example request:

```json
{
  "mode": "encode",
  "hdrInput": "/tmp/master.tiff",
  "sdrInput": "/tmp/base.jpg",
  "output": "/tmp/out.jpg",
  "quality": 90,
  "writeISO": true
}
```
