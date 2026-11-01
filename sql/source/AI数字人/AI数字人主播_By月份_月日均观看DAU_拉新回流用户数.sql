-- Presto / Spark 通用语法
-- ============================================================
-- 主题：AI 数字人主播 by月 by主播(带昵称) 的 月日均观看DAU / 月拉新用户数 / 月回流用户数
-- 源 UID 文件：C:\Users\tiany\Downloads\AI数字人的UID.txt（去重后 116 个）
-- ============================================================
-- 口径说明：
-- 1. 观看DAU：dwt_huya_ayyuid_session_from_server_with_user，tag='gameid' and htime='session'，
--    按 dt+luid+snick 聚合 count(distinct user_ukey) 得每天每主播观看用户数；
--    月日均 = 该主播当月各天观看用户数之和 / 该主播当月实际有数据天数(count distinct dt)。
--    （沿用 By月份主播观看月日均DAU_及对应的归属游戏.sql 的口径，未去黑产。）
-- 2. 拉新用户数：zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1，按 month+luid count distinct user_ukey。
-- 3. 回流用户数：zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1，按 month+luid count distinct user_ukey。
--    （拉新/回流表口径沿用 星秀户外拉新回流用户后7日表现_Spark_By主播.sql；此处不限定 game_id，纯按主播 luid 汇总。）
-- 4. 不限定品类：AI 数字人可能跨品类，所有指标纯按主播 luid 统计，不按 game_id 拆分。
-- 5. 昵称：优先取观看session表 snick，缺失时取拉新表 luid_name，再缺失取回流表 luid_name。
-- 6. 时间窗：2025-01-01 至 2026-07-28（7月统计至28日）。
--    各表最新分区可能不同，实际取数止于哪天见交付说明；若需精确建议先确认各表最新分区。
-- 7. 三个指标用 full outer join 合并，某主播某月只有观看没有拉新/回流时，对应列补 0。
-- 8. UID 列表用 values 内联表，Presto/Spark 通用，避免 array/explode 等高级语法。
-- ============================================================

with anchor_uids (luid) as (
  values
    (1199540008897),(1199635199657),(1199660531216),(1239543465979),
    (1239543827797),(1239543827798),(1239543827799),(1239543827800),
    (1239543827801),(1239543827802),(1239543827808),(1239543827809),
    (1239543827812),(1239543827813),(1239543827814),(1239543827815),
    (1239543827816),(1239543827817),(1239543827818),(1239543827819),
    (1239543827820),(1239543827821),(1239543827822),(1239543827823),
    (1239543827824),(1239543827825),(1239543827826),(1239543827891),
    (1239543827892),(1239543827895),(1239543827897),(1239543827898),
    (1239543827899),(1239543827900),(1239543827901),(1239543827926),
    (1239543827927),(1239543827928),(1239543827929),(1239543827930),
    (1239543827931),(1239543827932),(1239543827933),(1239543827934),
    (1239543827935),(1239543827936),(1239543827937),(1239543827938),
    (1239543827939),(1239543827940),(1239543827941),(1239543827952),
    (1239543827953),(1239543827954),(1239543827955),(1239543827956),
    (1239543827957),(1239543827958),(1239543827959),(1239543828246),
    (1239543828248),(1239543858785),(1239543858787),(1239543858789),
    (1239543858790),(1239543858791),(1239543858794),(1239543858796),
    (1239543858797),(1239543858798),(1239543858799),(1239543858800),
    (1239543858801),(1239543858803),(1239543858810),(1239543858811),
    (1239543858814),(1239543858830),(1239543858879),(1239543858881),
    (1239543858882),(1239543858883),(1239543858884),(1239543858885),
    (1239543858886),(1239543858887),(1239543858888),(1239543858889),
    (1239543858890),(1239543858891),(1239543858892),(1239543858893),
    (1239543858894),(1239543858895),(1239543858896),(1239543858907),
    (1239543858913),(1239543859080),(1239543859081),(1239543859082),
    (1239543859083),(1239543859084),(1239543859085),(1239543859086),
    (1239543859087),(1239543859088),(1239543859089),(1239543859090),
    (1239543859091),(1239543859100),(1239543859238),(1239543859239),
    (1239543859240),(1239543859241),(1239543859242),(1259513946208)
),

-- 每天每主播观看用户数（去重 user_ukey）
daily_view as (
  select
    a.dt,
    substr(a.dt, 1, 7) as month,
    a.luid,
    a.snick,
    count(distinct a.user_ukey) as daily_dau
  from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
  join anchor_uids u
    on a.luid = u.luid
  where a.dt between '2025-01-01' and '2026-07-28'
    and a.tag = 'gameid'
    and a.htime = 'session'
    and a.user_ukey is not null
  group by
    a.dt,
    substr(a.dt, 1, 7),
    a.luid,
    a.snick
),

-- 月日均观看DAU：该主播当月各天观看用户数之和 / 该主播当月有数据天数
anchor_month_dau as (
  select
    month,
    luid,
    max(snick) as snick,
    sum(daily_dau) * 1.0000 / count(distinct dt) as avg_daily_watch_dau
  from daily_view
  group by
    month,
    luid
),

-- 月拉新用户数
laxin_month as (
  select
    substr(a.dt, 1, 7) as month,
    a.luid,
    max(a.luid_name) as luid_name,
    count(distinct a.user_ukey) as laxin_user_cnt
  from zhgametemp.new_user_neirong_laxin_with_shichang_ukey_v1 a
  join anchor_uids u
    on a.luid = u.luid
  where a.dt between '2025-01-01' and '2026-07-28'
    and a.user_ukey is not null
  group by
    substr(a.dt, 1, 7),
    a.luid
),

-- 月回流用户数
huiliu_month as (
  select
    substr(a.dt, 1, 7) as month,
    a.luid,
    max(a.luid_name) as luid_name,
    count(distinct a.user_ukey) as huiliu_user_cnt
  from zhgametemp.huiliu_user_neirong_with_shichang_ukey_v1 a
  join anchor_uids u
    on a.luid = u.luid
  where a.dt between '2025-01-01' and '2026-07-28'
    and a.user_ukey is not null
  group by
    substr(a.dt, 1, 7),
    a.luid
)

-- 三指标 full outer join，按 月 + 主播 汇总
select
  coalesce(d.month, lx.month, hl.month) as month,
  coalesce(d.luid, lx.luid, hl.luid) as luid,
  coalesce(d.snick, lx.luid_name, hl.luid_name) as nickname,
  coalesce(d.avg_daily_watch_dau, 0) as avg_daily_watch_dau,
  coalesce(lx.laxin_user_cnt, 0) as laxin_user_cnt,
  coalesce(hl.huiliu_user_cnt, 0) as huiliu_user_cnt
from anchor_month_dau d
full outer join laxin_month lx
  on d.month = lx.month and d.luid = lx.luid
full outer join huiliu_month hl
  on coalesce(d.month, lx.month) = hl.month
 and coalesce(d.luid, lx.luid) = hl.luid
order by
  month,
  luid
