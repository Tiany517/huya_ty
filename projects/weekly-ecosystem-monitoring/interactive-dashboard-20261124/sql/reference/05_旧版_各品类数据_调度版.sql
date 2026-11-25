WITH game_labeled AS (
    SELECT
        CAST(gid AS VARCHAR) AS gameid,
        CASE
            WHEN game_full_name IN (
                '英雄联盟',
                '王者荣耀',
                'CS2',
                '体育',
                '户外',
                '一起看',
                '星秀',
                '无畏契约',
                '原创',
                '天天吃鸡',
                '主机游戏',
                '三角洲行动',
                '交友',
                'lol云顶之弈',
                '二次元',
                '穿越火线',
                '和平精英',
                '炉石传说',
                'DOTA2',
                '金铲铲之战'
            )
                THEN game_full_name
            ELSE '其他游戏'
        END AS game_name
    FROM (
        SELECT
            CAST(gid AS VARCHAR) AS gid,
            MAX(game_full_name) AS game_full_name
        FROM gamelive.to_main_games_day
        WHERE dt = '2026-09-06'
        GROUP BY
            CAST(gid AS VARCHAR)
    ) t
),

session_user_daily AS (
    SELECT
        s.dt,
        CAST(s.user_ukey AS VARCHAR) AS user_ukey,
        COALESCE(g.game_name, '其他游戏') AS game_name,
        SUM(COALESCE(s.user_duration, 0)) AS user_duration
    FROM gamelive.dwt_huya_ayyuid_session_from_server_with_user s
    LEFT JOIN game_labeled g
        ON CAST(s.igameid AS VARCHAR) = g.gameid
    WHERE s.dt BETWEEN '2026-08-31' AND '2026-09-06'
      AND s.tag = 'gameid'
      AND s.htime = 'session'
      AND s.user_product IN (
          'huya_andriod',
          'huya_ipad',
          'huya_pad',
          'huya_ios',
          'hmos_kiwi'
      )
      AND s.user_ukey IS NOT NULL
    GROUP BY
        s.dt,
        CAST(s.user_ukey AS VARCHAR),
        COALESCE(g.game_name, '其他游戏')
),

category_dau_daily AS (
    SELECT
        dt,
        game_name,
        COUNT(DISTINCT user_ukey) AS daily_dau,
        SUM(user_duration) AS total_user_duration
    FROM session_user_daily
    GROUP BY
        dt,
        game_name
),

overall_dau_daily AS (
    SELECT
        dt,
        COUNT(DISTINCT user_ukey) AS daily_dau,
        SUM(user_duration) AS total_user_duration
    FROM session_user_daily
    GROUP BY
        dt
),

category_revenue_daily AS (
    SELECT
        r.dt,
        COALESCE(g.game_name, '其他游戏') AS game_name,
        SUM(r.user_consume_amount) AS daily_revenue,
        COUNT(DISTINCT CAST(r.ext['ukey'] AS VARCHAR))
            AS daily_pay_user_cnt
    FROM zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i r
    LEFT JOIN game_labeled g
        ON CAST(r.game_id AS VARCHAR) = g.gameid
    WHERE r.dt BETWEEN '2026-08-31' AND '2026-09-06'
      AND r.user_consume_amount > 0
      AND r.ext['ukey'] IS NOT NULL
    GROUP BY
        r.dt,
        COALESCE(g.game_name, '其他游戏')
),

overall_revenue_daily AS (
    SELECT
        dt,
        SUM(user_consume_amount) AS daily_revenue,
        COUNT(DISTINCT CAST(ext['ukey'] AS VARCHAR))
            AS daily_pay_user_cnt
    FROM zhgametemp.hss_tichu_shuadan_dws_huya_revenue_detail_d_i
    WHERE dt BETWEEN '2026-08-31' AND '2026-09-06'
      AND user_consume_amount > 0
      AND ext['ukey'] IS NOT NULL
    GROUP BY
        dt
),

attribution_user_daily AS (
    SELECT DISTINCT
        a.dt,
        CAST(a.ukey AS VARCHAR) AS user_ukey,
        COALESCE(g.game_name, '其他游戏') AS game_name
    FROM zhgametemp.cwq_huya_ukey_shichang_luid_gameid_guishu_day_v1 a
    LEFT JOIN game_labeled g
        ON CAST(a.igameid AS VARCHAR) = g.gameid
    WHERE a.dt BETWEEN '2026-08-31' AND '2026-09-06'
      AND a.ukey IS NOT NULL
),

category_attribution_daily AS (
    SELECT
        dt,
        game_name,
        COUNT(DISTINCT user_ukey) AS daily_attribution_user_cnt
    FROM attribution_user_daily
    GROUP BY
        dt,
        game_name
),

overall_attribution_daily AS (
    SELECT
        dt,
        COUNT(DISTINCT user_ukey) AS daily_attribution_user_cnt
    FROM attribution_user_daily
    GROUP BY
        dt
),

interest_user_daily AS (
    SELECT
        i.dt,
        COALESCE(g.game_name, '其他游戏') AS game_name,
        SUM(i.user_pro) AS interest_user_cnt,
        SUM(
            CASE
                WHEN CAST(i.gameid AS VARCHAR) <> '1'
                    THEN i.user_pro
                ELSE 0
            END
        ) AS non_lol_interest_user_cnt
    FROM zhgametemp.cwq_huya_7days_xqzs_detail_tmp i
    LEFT JOIN game_labeled g
        ON CAST(i.gameid AS VARCHAR) = g.gameid
    WHERE i.dt BETWEEN '2026-08-31' AND '2026-09-06'
    GROUP BY
        i.dt,
        COALESCE(g.game_name, '其他游戏')
),

interest_overall_daily AS (
    SELECT
        dt,
        SUM(user_pro) AS interest_user_cnt,
        SUM(
            CASE
                WHEN CAST(gameid AS VARCHAR) <> '1'
                    THEN user_pro
                ELSE 0
            END
        ) AS non_lol_interest_user_cnt
    FROM zhgametemp.cwq_huya_7days_xqzs_detail_tmp
    WHERE dt BETWEEN '2026-08-31' AND '2026-09-06'
    GROUP BY
        dt
),

result AS (
    SELECT
        d.dt AS "日期",
        d.game_name AS "品类",
        d.daily_dau AS "DAU",

        COALESCE(r.daily_revenue, 0)
            AS "打赏流水",

        COALESCE(r.daily_pay_user_cnt, 0)
            AS "打赏人数",

        COALESCE(r.daily_revenue, 0)
            / NULLIF(r.daily_pay_user_cnt, 0)
            AS "人均打赏流水",

        d.total_user_duration / 1000.0 / 60
            / NULLIF(d.daily_dau, 0)
            AS "人均观时_分钟",

        COALESCE(a.daily_attribution_user_cnt, 0)
            AS "归因人数",

        COALESCE(i.interest_user_cnt, 0)
            AS "兴趣用户数",

        COALESCE(i.non_lol_interest_user_cnt, 0)
            AS "非LOL兴趣用户数"

    FROM category_dau_daily d
    LEFT JOIN category_revenue_daily r
        ON d.dt = r.dt
       AND d.game_name = r.game_name
    LEFT JOIN category_attribution_daily a
        ON d.dt = a.dt
       AND d.game_name = a.game_name
    LEFT JOIN interest_user_daily i
        ON d.dt = i.dt
       AND d.game_name = i.game_name

    UNION ALL

    SELECT
        d.dt AS "日期",
        '整体' AS "品类",
        d.daily_dau AS "DAU",

        COALESCE(r.daily_revenue, 0)
            AS "打赏流水",

        COALESCE(r.daily_pay_user_cnt, 0)
            AS "打赏人数",

        COALESCE(r.daily_revenue, 0)
            / NULLIF(r.daily_pay_user_cnt, 0)
            AS "人均打赏流水",

        d.total_user_duration / 1000.0 / 60
            / NULLIF(d.daily_dau, 0)
            AS "人均观时_分钟",

        COALESCE(a.daily_attribution_user_cnt, 0)
            AS "归因人数",

        COALESCE(i.interest_user_cnt, 0)
            AS "兴趣用户数",

        COALESCE(i.non_lol_interest_user_cnt, 0)
            AS "非LOL兴趣用户数"

    FROM overall_dau_daily d
    LEFT JOIN overall_revenue_daily r
        ON d.dt = r.dt
    LEFT JOIN overall_attribution_daily a
        ON d.dt = a.dt
    LEFT JOIN interest_overall_daily i
        ON d.dt = i.dt
)

SELECT
    "日期",
    "品类",
    "DAU",
    "打赏流水",
    "打赏人数",
    "人均打赏流水",
    "人均观时_分钟",
    "归因人数",
    "兴趣用户数",
    "非LOL兴趣用户数"
FROM result
ORDER BY
    "日期",
    CASE
        WHEN "品类" = '整体' THEN 0
        ELSE 1
    END,
    "DAU" DESC
