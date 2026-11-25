"""Render validated literal dates into reusable research SQL, never execute/write tables."""
import argparse
from datetime import date
from pathlib import Path

def render(source,start,end,snapshot):
    start=date.fromisoformat(start);end=date.fromisoformat(end);snapshot=date.fromisoformat(snapshot)
    if start>end or snapshot<end: raise ValueError('start <= end <= available snapshot required')
    return source.replace('{{START_DATE}}',str(start)).replace('{{END_DATE}}',str(end)).replace('{{SNAPSHOT_DATE}}',str(snapshot))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--start',required=True);p.add_argument('--end',required=True);p.add_argument('--snapshot',required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();src=Path(__file__).resolve().parent.parent/'sql/templates/赛事品类日并集阈值.sql'
    if a.output.exists(): raise SystemExit('refusing to overwrite existing SQL')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(render(src.read_text(encoding='utf-8'),a.start,a.end,a.snapshot),encoding='utf-8')
