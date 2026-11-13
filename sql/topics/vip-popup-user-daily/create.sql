-- Spark；新建独立日分区表，不覆盖已有曝光表。
create table if not exists zhgametemp.zty_vip_popup_type_user_d_i_v1 (
  popup_type string comment '拍脸配置定向人群类型，非独立身份鉴定',
  material_id string comment '后台配置ID，对应prop.material_id',
  uid string comment '有效登录用户yyuid',
  exposure_cnt bigint comment '当天该配置对该用户的曝光上报次数'
)
partitioned by (dt string comment '服务器stime自然日')
stored as orc;
