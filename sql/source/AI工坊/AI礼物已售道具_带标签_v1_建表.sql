-- ============================================================
-- AI礼物「已售道具 × 人工标签」维表
-- 表名   ：zhgametemp.zty_sold_gift_item_with_label_v1
-- 粒度   ：一行 = 一个被送出的 AI 礼物道具（item_id 粒度），共 5,551 行
-- 时间窗 ：2026-07-13 ~ 2026-09-14（底表 dws_huya_revenue_detail_d_i 的 dt 范围）
-- 来源   ：AI工坊被送出的礼物明细_清洗后_v8_en.csv
--          （底表 gamelive.dws_huya_revenue_detail_d_i + gamelive.dim_huya_item_d_a，
--            主播昵称来自 gamelive.dim_huya_ayyuid_info）
-- 标签   ：category_l1 / category_l2 为人工逐行打标结果，
--          口径见 人工打标/打标口径_v6_冻结版.md（一级 17 类、二级 42 类，冻结不得新增）
-- 分区   ：无分区（静态快照，全量一次性写入）
-- 覆盖   ：可覆盖；重跑请用 insert overwrite table
-- ============================================================
create table if not exists zhgametemp.zty_sold_gift_item_with_label_v1 (
    item_id               string   comment '礼物道具id，对应 dim_huya_item_d_a.item_id'
    ,item_name            string   comment '礼物道具名称，对应 dim_huya_item_d_a.item_name'
    ,category_l1          string   comment '一级类目，人工打标：主播IP/女性角色/动物/文字互动/场景与氛围/男性角色/美食饮品/诙谐低俗/CP/游戏动漫角色/道具/庆生与祝福/豪车载具/神话角色/其他/生活用品/惊悚'
    ,category_l2          string   comment '二级类目，人工打标；主播IP下分为 主播肖像/主播热梗/公会肖像/网友热梗'
    ,hyc_value            double   comment '礼物标准价值（元），对应 dim_huya_item_d_a.hyc_value'
    ,order_cnt            bigint   comment '打赏订单数（order_id 去重）'
    ,pay_user_cnt         bigint   comment '打赏人数（用户去重）'
    ,anchor_cnt           bigint   comment '被打赏主播数（主播去重）'
    ,sales_amount         double   comment '打赏金额合计（元），来自 dws_huya_revenue_detail_d_i.user_consume_amount'
    ,primary_anchor_id    bigint   comment '主主播uid，对应 dim_huya_ayyuid_info.uid'
    ,primary_anchor_name  string   comment '主主播昵称'
    ,second_anchor_name   string   comment '第二主播昵称'
    ,third_anchor_name    string   comment '第三主播昵称'
    ,user_prompt          string   comment '用户生成该AI礼物时填写的提示词'
)
comment 'AI礼物已售道具维表（含人工类目标签）；粒度=item_id；时间窗2026-07-13~2026-09-14；共5551行'
stored as orc
;
