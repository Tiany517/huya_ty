-- ============================================================
-- 全量主播近 30 天主品类（Presto 日跑调度）
-- 调度变量：${tdate?string('yyyy-MM-dd')}
--   tdate 表示本次取数截止日，一般传已就绪的 T-1。
-- 主播范围：gamelive 主播维表中 tdate 当天全部主播，不再限制 roomid。
-- 统计窗口：tdate-29 ~ tdate，共 30 个自然日。
-- 主品类：按主播 × game_id 汇总观众观看时长 user_duration，取最长品类；
--         并列时取 game_id 较小者，保证每个主播只有一条结果。
-- 输出粒度：主播；仅保留近 30 天存在有效品类观看记录的主播。
-- 建议落表：dt 分区 + 上述 5 个字段，每日覆盖当天分区。
-- ============================================================

with

-- 全量主播最新快照；按 uid 去重，避免昵称或房间信息变化造成重复
anchor_info as (
    select
        uid as luid,
        nick as snick,
        roomid
    from (
        select
            uid,
            nick,
            roomid,
            row_number() over (
                partition by uid
                order by create_time desc, roomid
            ) as rn
        from gamelive.dim_huya_ayyuid_info
        where dt = '${tdate?string('yyyy-MM-dd')}'
    ) t
    where rn = 1
),

-- 事实表先独立完成分区、口径和有效性过滤
anchor_game_session as (
    select
        luid,
        igameid,
        sgamename as game_name,
        user_duration
    from gamelive.dwt_huya_ayyuid_session_from_server_with_user
    where dt between '${DateUtils.addDays(tdate, -29)?string('yyyy-MM-dd')}'
                 and '${tdate?string('yyyy-MM-dd')}'
      and tag = 'gameid'
      and htime = 'session'
      and luid is not null
      and igameid is not null
      and user_duration > 0
),

-- 先在事实侧按主播 × 品类聚合，减少与主播维表关联的数据量
anchor_game_score_base as (
    select
        luid,
        igameid,
        max(game_name) as game_name,
        sum(user_duration) / 60000.0 as view_min
    from anchor_game_session
    group by
        luid,
        igameid
),

-- 补充主播昵称和直播间信息
anchor_game_score as (
    select
        b.luid,
        a.snick,
        a.roomid,
        b.igameid,
        b.game_name,
        b.view_min
    from anchor_game_score_base b
    inner join anchor_info a
        on b.luid = a.luid
),

-- 每个主播只保留观看时长最长的品类
anchor_main_game_ranked as (
    select
        luid,
        snick,
        roomid,
        igameid,
        game_name,
        view_min,
        row_number() over (
            partition by luid
            order by view_min desc, igameid
        ) as rn
    from anchor_game_score
)

select
    luid,
    snick,
    roomid,
    igameid as main_game_id,
    game_name as main_game_name
from anchor_main_game_ranked
where rn = 1;
