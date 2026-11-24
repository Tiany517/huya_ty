from __future__ import annotations

import base64
import gzip
import json
import sys
from pathlib import Path


template_path = Path(sys.argv[1])
data_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

data_bytes = data_path.read_bytes()
# Keep the dashboard portable as one file while avoiding a >50 MB text blob.
compressed_bytes = gzip.compress(data_bytes, compresslevel=9, mtime=0)
encoded_bytes = base64.b64encode(compressed_bytes).decode("ascii")
template = template_path.read_text(encoding="utf-8")
html = template.replace("__DASHBOARD_DATA_GZIP_BASE64__", encoded_bytes).replace("__DATA_BYTES__", str(len(data_bytes)))
output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(html, encoding="utf-8")
print(json.dumps({
    "output": str(output_path),
    "htmlBytes": output_path.stat().st_size,
    "dataBytes": data_path.stat().st_size,
    "compressedDataBytes": len(compressed_bytes),
    "embeddedBase64Bytes": len(encoded_bytes),
}, ensure_ascii=False, indent=2))
