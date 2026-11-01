-- ============================================================
-- AI礼物已售道具维表：CSV 导入（两段式，保留 ORC 正式表）
--
-- 报错定位：zty_sold_gift_item_with_label_v1 建表时是 stored as orc，
-- 而 LOAD DATA INPATH 只能往 textfile 落地表灌数据，
-- 所以抛 INVALID_FILE_FORMAT_IN_LOAD：
--   The file that you are trying to load does not match the file format of the destination table.
-- 另外 ALTER TABLE ... SET SERDEPROPERTIES('field.delim'=',') 救不了：
--   一是 ORC 表改 serde 无效，二是它在 LOAD 之后才执行，顺序也不对。
--
-- 处理思路：先灌到一张 textfile + OpenCSVSerde 的落地表，
--   再 insert overwrite 到 ORC 正式表，顺便做类型转换和脏行过滤。
--   必须用 OpenCSVSerde：CSV 里有 8 行 user_prompt 带英文逗号（被双引号包住），
--   LazySimpleSerDe 会把这些逗号当分隔符，列直接错位。
--
-- 上传文件：AI工坊被送出的礼物明细_清洗后_v8_en_nobom.csv（无 BOM 版本）
--   带 BOM 的版本会让 item_id 变成 '\ufeff30021215'，join 全废，务必用 nobom 那份。
-- ============================================================
use zhgametemp;

-- ------------------------------------------------------------
-- 1. 落地表：全部按 string 收，CSV 原样进，不做任何转换
-- ------------------------------------------------------------
drop table if exists zhgametemp.zty_sold_gift_item_with_label_v1_tmp;
create table zhgametemp.zty_sold_gift_item_with_label_v1_tmp (
    item_id              string
    ,item_name           string
    ,category_l1         string
    ,category_l2         string
    ,hyc_value           string
    ,order_cnt           string
    ,pay_user_cnt        string
    ,anchor_cnt          string
    ,sales_amount        string
    ,primary_anchor_id   string
    ,primary_anchor_name string
    ,second_anchor_name  string
    ,third_anchor_name   string
    ,user_prompt         string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
    'separatorChar' = ','
    ,'quoteChar'    = '"'
)
stored as textfile
;

-- ------------------------------------------------------------
-- 2. 把 HDFS 上传文件灌进落地表
--    路径按你截图里的上传地址，换文件后路径会变，注意同步
-- ------------------------------------------------------------
load data inpath 'hdfs://huyaecluster/tmp/data-dev/upload/1222019699806148096'
overwrite into table zhgametemp.zty_sold_gift_item_with_label_v1_tmp
;

-- ------------------------------------------------------------
-- 3. 落地表 → ORC 正式表：类型转换 + 脏行兜底过滤
--    regexp_replace 去 BOM 是防呆，用 nobom 文件时无副作用
-- ------------------------------------------------------------
insert overwrite table zhgametemp.zty_sold_gift_item_with_label_v1
select
    regexp_replace(trim(item_id), '\\uFEFF', '')   as item_id
    ,nullif(trim(item_name), '')                    as item_name
    ,nullif(trim(category_l1), '')                  as category_l1
    ,nullif(trim(category_l2), '')                  as category_l2
    ,cast(trim(hyc_value) as double)                as hyc_value
    ,cast(trim(order_cnt) as bigint)                as order_cnt
    ,cast(trim(pay_user_cnt) as bigint)             as pay_user_cnt
    ,cast(trim(anchor_cnt) as bigint)               as anchor_cnt
    ,cast(trim(sales_amount) as double)             as sales_amount
    ,cast(trim(primary_anchor_id) as bigint)        as primary_anchor_id
    ,nullif(trim(primary_anchor_name), '')          as primary_anchor_name
    ,nullif(trim(second_anchor_name), '')           as second_anchor_name
    ,nullif(trim(third_anchor_name), '')            as third_anchor_name
    ,nullif(trim(user_prompt), '')                  as user_prompt
from zhgametemp.zty_sold_gift_item_with_label_v1_tmp
where regexp_replace(trim(item_id), '\\uFEFF', '') rlike '^[0-9]{8}$'
;

-- ------------------------------------------------------------
-- 4. 导入校验：期望 row_cnt = item_cnt = 5551，sales_amount_total = 5493731，
--    ip_item_cnt = 1790
-- ------------------------------------------------------------
select
    count(1)                                                 as row_cnt
    ,count(distinct item_id)                                 as item_cnt
    ,sum(sales_amount)                                       as sales_amount_total
    ,sum(case when category_l1 = '主播IP' then 1 else 0 end) as ip_item_cnt
from zhgametemp.zty_sold_gift_item_with_label_v1
;

-- ------------------------------------------------------------
-- 5. 落地表用完可删（确认正式表校验通过后再执行）
-- ------------------------------------------------------------
-- drop table if exists zhgametemp.zty_sold_gift_item_with_label_v1_tmp;
