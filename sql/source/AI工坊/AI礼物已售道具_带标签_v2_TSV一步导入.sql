-- ============================================================
-- AI礼物已售道具维表 v2：用 TSV 一步导入（带类型，不需要落地表）
--
-- 你上次为什么"不分割"：建表语句里没有 row format，走的是 Hive 默认
-- LazySimpleSerDe，默认分隔符是 \001（Ctrl-A）而不是逗号，
-- 所以整行被塞进 item_id，后面 13 列全 NULL；表头那行也被当成数据进来了。
-- 另外 ALTER TABLE ..._v1 SET SERDEPROPERTIES('field.delim'=',') 改的是 v1，
-- 你 LOAD 的是 v2，表都对错了（而且建表后再 ALTER 分隔符本来就不稳）。
--
-- 正确做法：建表时就把分隔符写死。用 TSV 的原因——
--   逗号 CSV 有 8 行 user_prompt 自带英文逗号，用逗号分隔会列错位；
--   用 OpenCSVSerde 又会把 double/bigint 列读成 NULL。
--   数据本身没有制表符也没有换行，TSV 不需要引号，可以直接配 LazySimpleSerDe。
--
-- 上传文件：AI工坊被送出的礼物明细_清洗后_v8_en.tsv（UTF-8 无 BOM，含表头行）
-- 注意：LOAD DATA INPATH 是把文件【移动】进表目录，同一个路径不能重复 LOAD，
--       重跑必须重新上传，路径也会变。
-- ============================================================
use zhgametemp;

-- ------------------------------------------------------------
-- 1. 重建 v2：分隔符和表头跳过都在建表时写死
-- ------------------------------------------------------------
drop table if exists zhgametemp.zty_sold_gift_item_with_label_v2;
create table zhgametemp.zty_sold_gift_item_with_label_v2 (
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
row format delimited fields terminated by '\t'
tblproperties ('skip.header.line.count' = '1')
stored as textfile
;

-- ------------------------------------------------------------
-- 2. 导入（路径换成本次重新上传后的地址）
-- ------------------------------------------------------------
load data inpath 'hdfs://huyaeccluster/tmp/data-dev/upload/1222019069806148096'
overwrite into table zhgametemp.zty_sold_gift_item_with_label_v2
;

-- ------------------------------------------------------------
-- 3. 校验：期望 row_cnt = item_cnt = 5551
--    sales_amount_total = 5493731，ip_item_cnt = 1790
--    再顺手确认没有整行进第一列的残留（item_id 必须全是 8 位数字）
-- ------------------------------------------------------------
select
    count(1)                                                 as row_cnt
    ,count(distinct item_id)                                 as item_cnt
    ,sum(sales_amount)                                       as sales_amount_total
    ,sum(case when category_l1 = '主播IP' then 1 else 0 end) as ip_item_cnt
    ,sum(case when item_id rlike '^[0-9]{8}$' then 0 else 1 end) as bad_item_id_cnt
from zhgametemp.zty_sold_gift_item_with_label_v2
;
