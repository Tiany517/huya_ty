from __future__ import annotations

import json
import sys
from pathlib import Path


template_path = Path(sys.argv[1])
data_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

data_text = data_path.read_text(encoding="utf-8")
# Prevent an embedded nickname from prematurely closing the script block.
data_text = data_text.replace("</", "<\\/")
template = template_path.read_text(encoding="utf-8")
html = template.replace("__DASHBOARD_DATA__", data_text).replace("__DATA_BYTES__", str(data_path.stat().st_size))
output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(html, encoding="utf-8")
print(json.dumps({
    "output": str(output_path),
    "htmlBytes": output_path.stat().st_size,
    "dataBytes": data_path.stat().st_size,
}, ensure_ascii=False, indent=2))
