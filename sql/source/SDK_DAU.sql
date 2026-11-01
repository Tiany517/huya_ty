select 
  dt
  ,sum(case when type = 'qq观看dau' then dau else 0 end) as "qq观看dau"
  ,sum(case when type = 'qq预览dau' then dau else 0 end) as "qq预览dau"
  ,sum(case when type = 'qq宽口径dau' then dau else 0 end) as "qq宽口径dau"
  ,sum(case when type = '先锋观看dau' then dau else 0 end) as "先锋观看dau"
  ,sum(case when type = '先锋预览dau' then dau else 0 end) as "先锋预览dau"
  ,sum(case when type = '先锋宽口径dau' then dau else 0 end) as "先锋宽口径dau"
  ,sum(case when type = '百度贴吧流预览dau' then dau else 0 end) as "百度贴吧流预览dau"
  ,sum(case when type = '百度贴吧H5dau' then dau else 0 end) as "百度贴吧H5dau"
  ,sum(case when type = '手机百度流预览dau' then dau else 0 end) as "手机百度流预览dau"
  ,sum(case when type = '手机百度H5dau' then dau else 0 end) as "手机百度H5dau"
  ,sum(case when type = 'qq浏览器观看dau' then dau else 0 end) as "qq浏览器观看dau"
  ,sum(case when type = 'qq浏览器宽口径观看dau' then dau else 0 end) as "qq浏览器宽口径观看dau"
  ,sum(case when type = 'qq浏览器流预览dau' then dau else 0 end) as "qq浏览器流预览dau"
  ,sum(case when type = 'qq浏览器H5dau' then dau else 0 end) as "qq浏览器H5dau"
  ,sum(case when type = 'qq浏览器视频播放dau' then dau else 0 end) as "qq浏览器视频播放dau"
  ,sum(case when type = 'qq浏览器汇总dau' then dau else 0 end) as "qq浏览器汇总dau"
  ,sum(case when type = 'uc流预览dau' then dau else 0 end) as "uc流预览dau"
  ,sum(case when type = '夸克流预览dau' then dau else 0 end) as "夸克流预览dau"
  ,sum(case when type = 'uc+夸克H5dau' then dau else 0 end) as "uc+夸克H5dau"
  ,sum(case when type = '三星游戏中心视频播放dau' then dau else 0 end) as "三星游戏中心视频播放dau"
  ,sum(case when type = '应用宝视频播放dau' then dau else 0 end) as "应用宝视频播放dau"
  ,sum(case when type = '微软视频播放dau' then dau else 0 end) as "微软视频播放dau"
  ,sum(case when type = '微软视频曝光dau' then dau else 0 end) as "微软视频曝光dau"
  ,sum(case when type = '完美电竞pc_dau' then dau else 0 end) as "完美电竞pc_dau"
  ,sum(case when type = '完美电竞app_dau' then dau else 0 end) as "完美电竞app_dau"
from zhgametemp.zzz_huya_sdk_dau_v1
where dt >= '2026-06-01'
group by dt
order by dt