-- =====================================================================
-- 目的：虎视/虎啸（虎牙在抖音开设的 MCN）主播的 ACU、开播时长与观时明细
-- 口径：
--   站内来源 zhgametemp.zhubo_shengtai_platform_pinlei_dau_v4（platform='douyin' 归入虎啸 MCN）
--   虎视来源 gamelive.ads_spider_douyin_mcn_hushi_info_d_i
--   竞品（站外）日粒度来源 zhgametemp.yty_jingpin_anchor_vaild_dau
--   赛事窗口 gamelive.dwd_huya_dim_game_copyright_info_d_a，快照 dt='2026-10-08'，game_id=5937
--   观看人数 gamelive.dwt_huya_ayyuid_session_from_server_with_user，app 端，日均>=5万记为大比赛
-- 时间窗：2026-01-01 ~ 2026-10-15
-- 指标：view_mins = 有效ACU * 开播小时 * 60，单位为人·分钟
--       avg_view_mins 沿用原逻辑除以 t1.valid_acu，等价于 live_hours*60，口径待确认
-- =====================================================================

with t1 as (
	-- 站内生态表（抖音归到虎啸MCN）+ 虎视抓取表，统一成主播日粒度
	select
		if(platform = 'douyin', 'douyin-huxiao', platform) as platform,
		cast(dt as date) as dt,
		pinlei as pinlei,
		platform_id as anchor_id,
		nickname,
		cast(total_dau as double) as total_dau,
		cast(valid_dau as double) as valid_dau,
		cast(live_hours as double) as live_hours,
		cast(valid_acu as double) as valid_acu
	from zhgametemp.zhubo_shengtai_platform_pinlei_dau_v4
	where dt between '2026-01-01' and '2026-10-15'
		and platform in ('douyin', 'douyin-huxiao')
		and pinlei in ('无畏契约')

	union all

	select
		'douyin-hushi' as platform,
		cast(date as date) as dt,
		game_name as pinlei,
		aweme_display_id as anchor_id,
		max(nick_name) as nickname,
		cast(max(cast(watchuv as bigint)) as double) as total_dau,
		cast(max(cast(watchuv as bigint)) * 0.16 as double) as valid_dau,
		cast(max(cast(validliveduration as double)) as double) as live_hours,
		cast(max(cast(acu as double) / 4.6) as double) as valid_acu
	from gamelive.ads_spider_douyin_mcn_hushi_info_d_i
	where dt between '2026-01-01' and '2026-10-15'
		and date between '2026-01-01' and '2026-10-15'
		and cast(acu as double) > 0
		and game_name in ('无畏契约')
	group by date, aweme_display_id, game_name
),

t2 as (
	-- 竞品（站外）主播日粒度：开播分钟数与观时
	select
		cast(dt as date) as dt,
		r_lid,
		r_owner,
		vaild_acu,
		live_mins,
		watch_min
	from zhgametemp.yty_jingpin_anchor_vaild_dau
	where dt between '2026-01-01' and '2026-10-15'
		and pcode like '%douyin%'
),

match_anchor_info as (
	-- 赛事版权表：赛事与主播的对应关系（固定同一快照分区，避免多分区重复）
	select distinct
		substr(a.date, 1, 10) as dt,
		match_name,
		uid as luid
	from gamelive.dwd_huya_dim_game_copyright_info_d_a a
	where a.dt = '2026-10-08'
		and substr(a.date, 1, 10) between '2026-01-01' and '2026-12-31'
		and a.live_type like '%直播%'
		and a.game_id = 5937
),

match_info as (
	-- 每个赛事的起止日期
	select
		match_name,
		min(cast(substr(a.date, 1, 10) as date)) as min_dt,
		max(cast(substr(a.date, 1, 10) as date)) as max_dt
	from gamelive.dwd_huya_dim_game_copyright_info_d_a a
	where a.dt = '2026-10-08'
		and substr(a.date, 1, 10) between '2026-01-01' and '2026-12-31'
		and a.live_type like '%直播%'
		and a.game_id = 5937
	group by match_name
),

match_label as (
	-- 大比赛窗口：赛事窗口内 app 端日均观看人数 >= 5 万
	select
		a.match_name,
		b.min_dt,
		b.max_dt,
		date_diff('day', b.min_dt, b.max_dt) as gap_day_cnt,
		avg(a.user_cnt) as dau
	from (
		select
			a.dt,
			m.match_name,
			count(distinct a.user_ukey) as user_cnt
		from gamelive.dwt_huya_ayyuid_session_from_server_with_user a
		inner join match_anchor_info m
			on a.luid = m.luid
			and a.dt = m.dt
		where a.dt between '2026-01-01' and '2026-12-31'
			and a.tag = 'gameid'      -- 固定写法
			and a.htime = 'session'    -- 固定写法
			and a.user_product in ('huya_andriod','huya_ipad','huya_pad','huya_ios')  -- app端
		group by a.dt, m.match_name
	) a
	left join match_info b
		on a.match_name = b.match_name
	group by a.match_name, b.min_dt, b.max_dt
	having avg(a.user_cnt) >= 50000
)

select distinct
	t1.dt,
	date_trunc('week', t1.dt) as week_start,
	case when t1.dt between ml.min_dt and ml.max_dt then 1 else 0 end as is_big_match,
	case when t1.dt between ml.min_dt and ml.max_dt then ml.match_name else null end as match_name,
	t1.platform,
	t1.anchor_id,
	t1.nickname,
	t1.total_dau,
	t1.valid_dau,
	t1.valid_acu,
	t1.valid_acu * t1.live_hours * 60 as view_mins,
	(t1.valid_acu * t1.live_hours * 60) / nullif(t1.valid_acu, 0) as avg_view_mins,  -- 口径见文件头说明：等于 live_hours*60
	t2.live_mins
from t1
left join t2
	on t1.dt = t2.dt
	and t1.nickname = t2.r_owner
left join match_label ml
	on t1.dt between ml.min_dt and ml.max_dt
where t1.nickname like '%月子%'   -- 单主播排查用，按需替换或删除
order by t1.dt
