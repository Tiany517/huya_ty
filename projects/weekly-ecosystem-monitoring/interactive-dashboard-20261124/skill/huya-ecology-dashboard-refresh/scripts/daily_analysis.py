"""Analyst workbench: complete weekday baselines, signed persistence and revenue bridge."""
from datetime import timedelta
import html
import json
import statistics


def revenue_bridge(current_revenue, baseline_revenue, current_pay, baseline_pay):
    if current_pay <= 0 or baseline_pay <= 0:
        return None
    current_arppu = current_revenue / current_pay
    baseline_arppu = baseline_revenue / baseline_pay
    pay_effect = (current_pay - baseline_pay) * (current_arppu + baseline_arppu) / 2
    arppu_effect = (current_arppu - baseline_arppu) * (current_pay + baseline_pay) / 2
    return dict(currentArppu=current_arppu, baselineArppu=baseline_arppu,
                payEffect=pay_effect, arppuEffect=arppu_effect,
                residual=current_revenue - baseline_revenue - pay_effect - arppu_effect)


def build_analysis(report_date, by_category, dimensions, classify):
    records = []
    for idx, current in by_category.get(report_date.isoformat(), {}).items():
        category = dimensions['categories'][idx]
        for metric in ('dau', 'revenue', 'payUsers', 'attributionUsers', 'liveAnchors'):
            def measure(day):
                dates = [day - timedelta(days=7 * n) for n in range(1, 5)]
                values = [by_category.get(d.isoformat(), {}).get(idx) for d in dates]
                today = by_category.get(day.isoformat(), {}).get(idx)
                if today is None or any(v is None or v.get(metric) is None for v in values) or today.get(metric) is None:
                    return None
                return classify(metric, float(today[metric]), [float(v[metric]) for v in values])
            change = measure(report_date)
            if change is None:
                continue
            streak = 0
            cumulative = 0
            first = None
            for offset in range(28):
                day = report_date - timedelta(days=offset)
                past = measure(day)
                if past is None or past['severity'] == '正常' or past['delta'] * change['delta'] <= 0 or change['severity'] == '正常':
                    break
                streak += 1
                cumulative += past['delta']
                first = day.isoformat()
            baseline_days = [by_category[(report_date - timedelta(days=7*n)).isoformat()][idx] for n in range(1,5)]
            bridge = None
            if metric == 'revenue' and all(v.get('payUsers') is not None for v in baseline_days):
                bridge = revenue_bridge(change['current'], change['baseline'], float(current.get('payUsers') or 0),
                                        statistics.median(float(v['payUsers']) for v in baseline_days))
            records.append(dict(change, name=category['name'], group=dimensions['groups'][int(category['group'])],
                                streak=streak, first=first, cumulative=cumulative, capped=streak == 28, bridge=bridge))
    return records


def render_analysis(records):
    payload = json.dumps(records, ensure_ascii=False).replace('<', '\\u003c')
    return '''<section id="analystWorkbench"><div class="section-head"><div><h2>异动分析工作台</h2>
    <p>全品类候选 · 报告日对过去4个同星期中位数 · 选择指标后重新排序</p></div></div>
    <div class="section-body"><label>指标 <select id="analysisMetric"><option value="dau">观看 DAU</option><option value="revenue">打赏流水（元）</option><option value="payUsers">打赏人数</option><option value="attributionUsers">归属用户数</option><option value="liveAnchors">开播主播数</option></select></label>
    <label>排序 <select id="analysisOrder"><option value="loss">下降优先排查</option><option value="absolute">变化绝对值</option><option value="streak">持续异常天数</option></select></label>
    <label>Top <input id="analysisLimit" type="number" min="1" max="100" value="10" style="width:70px"></label>
    <div style="overflow:auto"><table><thead><tr><th>品类</th><th>内容大类</th><th>报告日值</th><th>同星期基线</th><th>变化值</th><th>变化率</th><th>异常级别</th><th>连续异常天数</th><th>首次出现</th><th>连续期累计偏离</th><th>付费人数效应（元）</th><th>ARPPU效应（元）</th></tr></thead><tbody id="analysisRows"></tbody></table></div>
    <p style="color:var(--muted);font-size:12px">下降优先排查：按负向绝对变化由大到小；持续天数作为同值时排序依据。异常级别沿用各指标原阈值和异常分，不能等同业务优先级。连续异常须方向一致，每天均有4个完整同星期基线；缺记录即中断，不补零。最多回溯28天，达到上限显示“≥28”。累计偏离是每日值与各自基线之差的求和，人数类属于人次，不能当作去重流失人数。流水用付费人数×ARPPU对称拆解，两个效应之和等于流水变化；基线ARPPU=流水中位数÷付费人数中位数，零分母时不拆解。数值拆解不代表因果。</p>
    </div></section><script>(function(){const data=__ANALYSIS_DATA__;
    const esc=v=>String(v??'—').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const fmt=v=>v==null?'—':Number(v).toLocaleString('zh-CN',{maximumFractionDigits:2});
    function render(){const metric=document.getElementById('analysisMetric').value,order=document.getElementById('analysisOrder').value;
    const limit=Math.max(1,Math.min(100,Number(document.getElementById('analysisLimit').value)||10));
    let rows=data.filter(r=>r.metric===metric);if(order==='loss')rows=rows.filter(r=>r.delta<0);
    rows.sort((a,b)=>order==='streak'?b.streak-a.streak||Math.abs(b.delta)-Math.abs(a.delta):order==='loss'?a.delta-b.delta||b.streak-a.streak:Math.abs(b.delta)-Math.abs(a.delta));
    document.getElementById('analysisRows').innerHTML=rows.slice(0,limit).map(r=>'<tr>'+[r.name,r.group,fmt(r.current),fmt(r.baseline),fmt(r.delta),r.changePct==null?'—':(r.changePct*100).toFixed(1)+'%',r.severity,(r.capped?'≥':'')+r.streak,r.first,fmt(r.cumulative),fmt(r.bridge?.payEffect),fmt(r.bridge?.arppuEffect)].map(v=>'<td>'+esc(v)+'</td>').join('')+'</tr>').join('')||'<tr><td colspan="12">当前指标无符合条件的对象，或基线不足</td></tr>';}
    ['analysisMetric','analysisOrder','analysisLimit'].forEach(id=>document.getElementById(id).addEventListener('change',render));render();window.__analystAnalysis={data,render};})();</script>'''.replace('__ANALYSIS_DATA__', payload)
