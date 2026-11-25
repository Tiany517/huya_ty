"""Dated exploratory evidence; never infer tournament status from missing mappings."""
import html
import json
import math
from datetime import date


def load_context(path, report_date):
    if not path:
        return None
    context = json.loads(path.read_text(encoding="utf-8-sig"))
    if context["reportDate"] != str(report_date):
        raise ValueError("赛事诊断日期与日报不一致，禁止沿用过期样本")
    if date.fromisoformat(context["comparisonDate"]) >= date.fromisoformat(str(report_date)):
        raise ValueError("赛事对比日期须早于报告日")
    for row in context["metrics"]:
        for key in ("current", "previous"):
            value = row[key]
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise ValueError("赛事诊断指标必须是非负有限数值")
    return context


def render_context(context):
    if not context:
        return ('<section><div class="section-head"><h2>赛事核查</h2><p>待接入</p></div>'
                '<div class="section-body">未提供对应报告日的赛事诊断。品类下降须同时核对同品类供给、赛程、赛事关联主播与固定名单流量；不能直接认定为生态恶化。</div></section>')
    esc = lambda value: html.escape(str(value))
    rows = []
    for row in context["metrics"]:
        current, previous = row["current"], row["previous"]
        change = f"{(current / previous - 1):+.2%}" if previous else "基期为零"
        rows.append(f'<tr><td>{esc(row["label"])}</td><td>{current:,.0f}</td><td>{previous:,.0f}</td><td>{current-previous:+,.0f}</td><td>{change}</td><td>{esc(row["scope"])}</td></tr>')
    notes = ''.join(f'<li>{esc(note)}</li>' for note in context["notes"])
    sources = ''.join(f'<li>{esc(source)}</li>' for source in context["sources"])
    return (f'<section id="tournamentContext"><div class="section-head"><h2>赛事与拉新回流核查 · {esc(context["category"])}</h2>'
            f'<p>{esc(context["reportDate"])} 对比 {esc(context["comparisonDate"])}｜探索抽样，不代表全品类验收</p></div>'
            '<div class="table-wrap"><table><thead><tr><th>指标</th><th>本期（日）</th><th>对比期（日）</th><th>变化值</th><th>变化率</th><th>范围 / 来源</th></tr></thead><tbody>'
            + ''.join(rows) + '</tbody></table></div><div class="section-body"><ul>' + notes
            + '</ul><details><summary>证据来源与验证范围</summary><ul>' + sources + '</ul></details></div></section>')
