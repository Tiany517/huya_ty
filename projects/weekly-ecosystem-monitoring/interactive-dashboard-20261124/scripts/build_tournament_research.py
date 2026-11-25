"""Reconcile bounded tournament research exports; never publish production labels."""
import argparse
import ast
import csv
import html
import io
import json
import statistics
from pathlib import Path


def read_export(root, name):
    payload = ast.literal_eval((root / (name + '.txt')).read_text(encoding='utf-8'))
    if payload.get('success') is not True or not payload.get('data'):
        raise ValueError('Result unavailable: ' + name)
    return list(csv.DictReader(io.StringIO(payload['data'].lstrip('\ufeff'))))


def table(headers, rows):
    esc = lambda value: html.escape(str(value))
    return '<div class="scroll"><table><thead><tr>' + ''.join('<th>'+esc(x)+'</th>' for x in headers) + '</tr></thead><tbody>' + ''.join('<tr>'+''.join('<td>'+esc(x)+'</td>' for x in row)+'</tr>' for row in rows) + '</tbody></table></div>'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--dashboard-data', type=Path, required=True)
    args = parser.parse_args()
    root = args.evidence_dir
    events = read_export(root, '阈值探索_原始返回')
    corrected = read_export(root, '异常ID修正_原始返回')
    events = [r for r in events if r['gameid'] not in ('5937', '8127')] + corrected
    calendar = read_export(root, '标准化完整排期_原始返回')
    thresholds = read_export(root, '品类赛事并集阈值_原始返回')
    peaks = read_export(root, '独立峰值_原始返回')
    daily = read_export(root, '赛后周拆解_原始返回')
    supply = read_export(root, '赛后周开播数_原始返回')
    names = {r['gameid']: r['game_name'] for r in read_export(root, '品类字典_原始返回')}
    dashboard = json.loads(args.dashboard_data.read_text(encoding='utf-8'))
    dims = dashboard['meta']['categories']
    names.update({r['id']: r['name'] for r in dims})
    threshold_by_id = {r['gameid']: r for r in thresholds}
    calendar_by_key = {(r['gameid'], r['match_id']): r for r in calendar}
    checks = {
        'eventKeysUnique': len({(r['gameid'],r['match_id']) for r in events}) == len(events),
        'calendarKeysUnique': len(calendar_by_key) == len(calendar),
        'thresholdKeysUnique': len(threshold_by_id) == len(thresholds),
        'fiveIndependentPeaks': len(peaks) == 5 and all(any(e['gameid']==r['gameid'] and e['peak_date']==r['dt'] and int(e['peak_event_dau'])==int(r['dau']) for e in events) for r in peaks),
        'unionPeakNotBelowSingleEvent': all(int(threshold_by_id[e['gameid']]['peak_dau']) >= int(e['peak_event_dau']) for e in events),
        'categoryPercentilesOrdered': all(int(r['p50'])<=int(r['p75'])<=int(r['p90'])<=int(r['p95'])<=int(r['peak_dau']) for r in thresholds),
        'cycle42UniqueRows': len(daily)==42 and len({(r['dt'],r['gameid']) for r in daily})==42,
        'supply42UniqueRows': len(supply)==42 and len({(r['dt'],r['gameid']) for r in supply})==42,
        'exclusiveBucketsClose': all(int(r['fixed_only'])+int(r['other_only'])+int(r['overlap'])==int(r['app_dau']) and int(r['fixed_only'])+int(r['overlap'])==int(r['fixed_cohort_dau']) for r in daily),
    }
    if not all(checks.values()):
        raise ValueError(json.dumps(checks))
    coverage = []
    for gid in sorted({r['id'] for r in dims} | {r['gameid'] for r in calendar}, key=lambda x: names.get(x,x)):
        t = threshold_by_id.get(gid)
        ev = [e for e in calendar if e['gameid']==gid]
        status = '无版权赛事记录，不能判断为无赛事' if not ev else '有登记但未匹配观看，待核查'
        if t:
            status = '样本有限，仅描述' if int(t['positive_calendar_days']) < 30 or len(ev)<3 else '可比较分位线，尚未正式定级'
        coverage.append({'gameid':gid, 'game_name':names.get(gid,gid), 'mapped_events':len(ev),
                         'positive_days':t['positive_calendar_days'] if t else '',
                         **{key: t[key] if t else '' for key in ('p50','p75','p90','p95')}, 'status':status})
    with (root/'全品类赛事覆盖与阈值.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(coverage[0]));writer.writeheader();writer.writerows(coverage)
    with (root/'单赛事周期统计_标准化.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(events[0]));writer.writeheader();writer.writerows(events)
    fmt=lambda x: f'{float(x):,.0f}'
    pct=lambda a,b: f'{(a/b-1):+.2%}' if b else '基期为零'
    threshold_rows=[]
    for r in sorted((r for r in coverage if r['mapped_events']),key=lambda r:float(r['p90'] or 0),reverse=True):
        threshold_rows.append([r['game_name'],r['gameid'],r['mapped_events'],r['positive_days'] or '—',*[fmt(r[k]) if r[k] else '—' for k in ('p50','p75','p90','p95')],r['status']])
    cycle_rows=[]
    decomposition=[]
    cycle_names={'1':'全球总决赛关联主播','2336':'KPL年度总决赛关联主播','862':'BLAST香港关联主播（观察样本，非P90大赛认定）'}
    for gid in ('1','2336','862'):
        values={}
        for key in ('app_dau','fixed_cohort_dau','fixed_only','other_only','overlap'):
            current=[int(r[key]) for r in daily if r['gameid']==gid and r['dt']>='2026-11-16']
            previous=[int(r[key]) for r in daily if r['gameid']==gid and r['dt']<='2026-11-15']
            assert len(current)==len(previous)==7
            values[key]=(statistics.mean(current),statistics.mean(previous))
        cs=[int(r['live_anchors']) for r in supply if r['gameid']==gid and r['dt']>='2026-11-16']
        ps=[int(r['live_anchors']) for r in supply if r['gameid']==gid and r['dt']<='2026-11-15']
        assert len(cs)==len(ps)==7
        cycle_rows.append([names[gid],cycle_names[gid],*[fmt(v) for v in values['app_dau']],pct(*values['app_dau']),pct(*values['fixed_cohort_dau']),pct(statistics.mean(cs),statistics.mean(ps))])
        for key,label in [('fixed_only','仅看该固定名单'),('other_only','仅看名单外主播'),('overlap','两者都看')]:
            a,b=values[key];decomposition.append([names[gid],label,fmt(a),fmt(b),fmt(a-b)])
        assert abs(sum(values[k][0]-values[k][1] for k in ('fixed_only','other_only','overlap'))-(values['app_dau'][0]-values['app_dau'][1]))<0.000001
    sample_rows=[]
    for gid,mid in [('1','9029206'),('1','9029204'),('2336','9029410'),('2336','9029419'),('2336','9031112'),('862','9029512')]:
        e=next(e for e in events if e['gameid']==gid and e['match_id']==mid)
        c=calendar_by_key[(gid,mid)]
        sample_rows.append([names[gid],e['match_name'],c['known_start'],c['known_end'],c['mapped_days_in_window'],e['observed_days'],fmt(e['mean_event_dau']),fmt(e['peak_event_dau'])])
    sections=[
        ('核查范围与结论', ['近180天：2026-05-29至2026-11-24；版权快照2026-11-24。观看分区180天连续，实际数据截至11月24日。',
         f'按全品类版权记录排查，标准化后覆盖{len(calendar)}个品类×赛事组合、{len(set(r["gameid"] for r in calendar))}个品类；其中{len(thresholds)}个品类有匹配观看。完整覆盖清单另存CSV；无记录仅表示当前数据源未覆盖，不能当作非赛事。',
         '赛事DAU沿用原SQL：is_app=1、is_watch>0、is_black=0，不含鸿蒙。这里是赛事关联主播整日覆盖DAU，不能称精确比赛时段DAU。',
         '下表为探索分位线，不是已批准的大赛事阈值。官方赛程核验尚未覆盖所有候选，正式赛事标签保持待验证。']),
        ('建议怎样定义大赛事', ['先按品类同日全部赛事观看用户并集计算P50/P75/P90/P95；P90用于标记高赛事流量日，不能仅凭峰值越线就把整场赛事定为大赛，也不能把未越线的比赛日叫非赛事期。',
         '再按赛事ID回看整个赛期的有观看赛日日均、峰值、越线持续天数、占同源品类DAU比例和赛程阶段。长赛事与一日庆典分开核查，避免只因赛事较长或单日冲高而定级。',
         'P90是较严格候选线，P75是较宽候选线；应比较入选赛事和漏选清单后确定。历史不足30个有观看日或少于3场赛事，本报告只描述分布，不给正式等级。该样本门槛是探索提示，不是经校准的统计置信标准。',
         '例如MSI是已知主要赛事，但单场峰值313万低于LOL品类赛事并集P90约337万；因此“峰值过P90”不能作为唯一的大赛识别条件。CS2香港赛虽未达到历史P90，仍有约96万赛事日均覆盖，不应从流量解释中消失。']),
        ('赛事周期与归因边界', ['完整自然周对比：本期2026-11-16—11-22，前期2026-11-09—11-15，均为7日求均，不是周去重UV。与日报11/24对过去4个同星期中位数是不同基线。',
         '固定名单分别取全球总决赛、KPL年度总决赛、BLAST香港赛版权登记主播，跨两周冻结。名单DAU含这些主播日常直播；赛事前后变化属于描述性结构拆解，不等于比赛的净因果效应。',
         '同品类开播主播数来自生态健康表主播明细有效UID且is_live=1的日去重数。供给只做旁证，不与BP用户数相加。仅看固定名单、仅看名单外、两者都看是互斥桶，三者DAU变化精确闭合。',
         'LOL周DAU下降而同品类开播主播数基本持平，且下降集中在固定赛事名单覆盖用户，符合赛后流量回落特征；但仍需赛前/同阶段及排除同期其他事件的对照，不能写成已证明赛事造成全部下降。王者的名单外用户也下降，需要继续排查常规内容流量。']),
        ('数据问题与外部核验', ['版权game_id出现中文“无畏契约”“王者万象棋”，维表唯一对应5937、8127；保留原始返回并独立补算。无畏契约原阈值受漏匹配影响，本报告采用修正后的结果。',
         '原始全量Presto关联触发8GB内存限制；Spark失败且平台未返回错误详情；调整为过滤后的观看事实关联去重赛事映射后Presto成功。不能据此推断Spark失败原因。',
         'LOL官方赛程：https://lolesports.com/pl-PL/news/worlds-2026-primer，决赛北京时间11/15；版权表赛期10/16—11/15。其余表中日期为内部登记起止，不冒充官方已核验日期。',
         '王者联网核查找到ChinaJoy认证公告 https://www.sina.cn/news/detail/5361227272554164.html ，正文确认决赛与巅峰之夜活动，但未提供可核验日期；不能据搜索AI概览标记官方赛程通过。',
         '体育2356等品类在该版权源观察窗未检出登记，不能据此认定无大型体育赛事。已找到历史斯诺克独立主播名单SQL，但不能将旧名单和旧排期直接冒充本期全体育赛事映射。']),
        ('核验状态', ['分区覆盖、结果唯一键、分位线顺序、品类并集峰值不低于单赛事峰值、42行周拆解和42行供给数据的日期完整性均通过。',
         'LOL、王者、CS2、无畏契约、DOTA2共5个峰值用独立半连接重算，与主查询完全一致；42行用户互斥桶及周变化闭合。',
         '尚未完成：所有赛事日逐日独立复算、正式阈值校准、全候选官方赛程验证、体育等未覆盖赛事源接入、赛事流水/拉新/回流完整周期分析。因此本报告状态为探索，不发布正式生产标签。'])
    ]
    tables=[('各品类赛事DAU并集分布（不含鸿蒙）',['品类','品类ID','登记赛事数','有观看自然日','P50','P75','P90','P95','状态'],threshold_rows),
            ('重点赛事完整周期统计（内部排期）',['品类','赛事','登记开始','登记结束','登记赛日','有观看赛日','有观看赛日日均DAU','峰值DAU'],sample_rows),
            ('结束前后完整周对比',['品类','固定名单','本期日均DAU','前期日均DAU','品类DAU变化率','固定名单DAU变化率','同品类开播数变化率'],cycle_rows),
            ('互斥用户桶拆解',['品类','用户桶','本期日均DAU','前期日均DAU','变化值'],decomposition)]
    md=['# 全品类赛事阈值与周期诊断｜2026-11-25','', '**状态：探索；未发布正式大赛事标签。**','']
    body='<h1>赛事阈值与周期诊断</h1><p class="meta">2026-11-25 · 数据截至11月24日 · 探索研究，非正式赛事定级</p>'
    for title, paragraphs in sections:
        md += ['## '+title,'']+['- '+p for p in paragraphs]+['']
        body += '<section><h2>'+html.escape(title)+'</h2>'+''.join('<p>'+html.escape(p)+'</p>' for p in paragraphs)+'</section>'
    for title,headers,rows in tables:
        md += ['## '+title,'','| '+' | '.join(headers)+' |','|'+'|'.join('---' for _ in headers)+'|']+['| '+' | '.join(map(str,row))+' |' for row in rows]+['']
        body += '<section><h2>'+html.escape(title)+'</h2>'+table(headers,rows)+'</section>'
    (root/'赛事阈值与周期诊断_20261125.md').write_text('\n'.join(md),encoding='utf-8')
    css='body{margin:0;background:linear-gradient(135deg,#eef3fa,#f7f4fc);font:14px/1.8 "Microsoft YaHei",sans-serif;color:#253248}main{max-width:1320px;margin:40px auto;padding:0 24px}h1{font-size:28px;margin:0}h2{font-size:18px}.meta{color:#738196}section{margin:20px 0;padding:24px;border:1px solid #fff;border-radius:22px;background:#ffffffb8;box-shadow:0 8px 30px #283b5b08}p{margin:8px 0}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:12px;font-variant-numeric:tabular-nums}th,td{padding:10px 12px;white-space:nowrap;text-align:left;border-bottom:1px solid #e9edf4}th{background:#f3f6fb;color:#61718b}'
    (root/'赛事阈值与周期诊断_20261125.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>赛事阈值与周期诊断</title><style>'+css+'</style><main>'+body+'</main></html>',encoding='utf-8')
    (root/'研究核查结果.json').write_text(json.dumps({'status':'exploratory','checks':checks,'categoriesWithMappings':len(set(r['gameid'] for r in calendar)),'categoriesWithViewing':len(thresholds),'eventKeys':len(events)},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'status':'exploratory','checks':checks,'thresholdCategories':len(thresholds),'mappedCategories':len(set(r['gameid'] for r in calendar)),'coverageRows':len(coverage)},ensure_ascii=False))


if __name__ == '__main__':
    main()
