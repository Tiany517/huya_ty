select 
  dt
  ,sum(case when type = 'qq宽口径mau' then mau else 0 end) as "qq宽口径mau"
  ,sum(case when type = '先锋宽口径mau' then mau else 0 end) as "先锋宽口径mau"
  ,sum(case when type = '百度贴吧流预览mau' then mau else 0 end) as "百度贴吧流预览mau"
  ,sum(case when type = '百度贴吧H5mau' then mau else 0 end) as "百度贴吧H5mau"
  ,sum(case when type = '手机百度流预览mau' then mau else 0 end) as "手机百度流预览mau"
  ,sum(case when type = '手机百度H5mau' then mau else 0 end) as "手机百度H5mau"
  ,sum(case when type = 'qq浏览器宽口径观看mau' then mau else 0 end) as "qq浏览器宽口径观看mau"
  ,sum(case when type = 'qq浏览器流预览mau' then mau else 0 end) as "qq浏览器流预览mau"
  ,sum(case when type = 'qq浏览器H5mau' then mau else 0 end) as "qq浏览器H5mau"
  ,sum(case when type = 'qq浏览器视频播放mau' then mau else 0 end) as "qq浏览器视频播放mau"
  ,sum(case when type = 'qq浏览器汇总mau' then mau else 0 end) as "qq浏览器汇总mau"
  ,sum(case when type = 'uc流预览mau' then mau else 0 end) as "uc流预览mau"
  ,sum(case when type = '夸克流预览mau' then mau else 0 end) as "夸克流预览mau"
  ,sum(case when type = 'uc+夸克H5mau' then mau else 0 end) as "uc+夸克H5mau"
  ,sum(case when type = '三星视频播放mau' then mau else 0 end) as "三星视频播放mau"
  ,sum(case when type = '应用宝视频播放mau' then mau else 0 end) as "应用宝视频播放mau"
  ,sum(case when type = '微软视频播放mau' then mau else 0 end) as "微软视频播放mau"
  ,sum(case when type = '微软视频曝光mau' then mau else 0 end) as "微软视频曝光mau"
  ,sum(case when type = '完美电竞pc_mau' then mau else 0 end) as "完美电竞pc_mau"
  ,sum(case when type = '完美电竞app_mau' then mau else 0 end) as "完美电竞app_mau"
from zhgametemp.zzz_huya_sdk_mau_v1
where dt >= '2026-06-01'
group by dt
order by dt