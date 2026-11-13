# SQL学习笔记

持续整理实际分析中遇到的 SQL 写法，先解释用途，再解释函数。示例采用 Presto；均为教学片段，不代表已验证的完整业务查询。

## 1. 给普通用户分配一个观察起点

VIP 有购卡时间，普通用户没有。为了比较起点后30天的打赏率，可以为每个普通用户固定选择一位 VIP，借用该 VIP 的购卡时间。这里只是分配时间，不是匹配相似用户。

```sql
normal_start as (
  -- 输入：普通用户每个UID一行；VIP每个编号一行。
  -- 输出：每个普通用户一行，保留UID和观察起点。
  select
    n.uid,
    s.start_ts
  from normal_user n
  inner join vip_start s
    on mod(crc32(to_utf8(n.uid)), s.start_cnt) + 1 = s.start_no
)
```

其中 `vip_start` 需要预先生成以下字段：

```sql
select
  uid,
  start_ts,
  row_number() over (order by start_ts, uid) as start_no,
  count(*) over () as start_cnt
from vip_user;
```

| 字段 | 含义 |
| --- | --- |
| `uid` | VIP用户UID |
| `start_ts` | 该VIP首次购卡时间 |
| `start_no` | VIP编号，从1开始；排序必须稳定 |
| `start_cnt` | 当前VIP名单总人数，每行相同 |

### 1.1 函数逐步拆解

```sql
to_utf8(n.uid)                  -- UID字符串 → UTF-8字节
crc32(to_utf8(n.uid))           -- 字节 → 固定的整数校验值
mod(crc32(to_utf8(n.uid)), 3)   -- 除以3取余数，结果为0、1、2
mod(crc32(to_utf8(n.uid)), 3)+1 -- 加1，结果对应VIP编号1、2、3
```

普通用户没有预先生成编号。表达式是在关联时临时算出“选择哪个VIP编号”。CRC32不是加密，也不能作为用户唯一键；不同UID可能产生相同校验值或余数。

假设两个UID的校验值分别为10和13，以下数字仅用于演示取余，并非某个真实UID的CRC32结果：

| 普通用户 | 假设校验值 | 除以3的余数 | 加1后的选择数字 | 结果 |
| --- | ---: | ---: | ---: | --- |
| A | 10 | 1 | 2 | 借用第2位VIP的购卡时间 |
| B | 13 | 1 | 2 | 同样借用第2位VIP的购卡时间 |

多个普通用户可以选择同一位VIP；只要VIP编号唯一且从1连续到总人数，每个普通用户就只匹配一个起点。同一UID和同一份VIP名单在稳定排序下会得到相同结果；VIP名单变化后，分配也可能变化。这是固定分配，不是抽样，不保证有限样本中的日期占比完全一致，也不是1∶1配对。

### 1.2 分配起点与对齐活跃程度是两步

1. 分配起点：让每个普通用户有一个用于回看历史、观察后续的时间。
2. 统计活跃：统计每个人各自起点前30个自然日的去重活跃天数，不含起点当天。
3. 算门槛：在起点前12个月无打赏的目标VIP中计算平均活跃天数，并向上取整。
4. 筛两组：VIP和普通用户都要求活跃天数达到该门槛，并且各自起点前12个月无打赏。
5. 算比例：各组起点后30天内打赏人数 / 各组符合条件人数。

```sql
ceil(avg(cast(active_day_cnt as double))) as min_active_days
```

例如均值为18.3天，共同门槛为活跃至少19天。门槛应在筛选前计算一次，不能在达标者中反复重算。达到同一门槛不代表两组平均活跃天数相等，更不代表因果可比。

## 2. 数组、filter和Lambda表达式

```sql
array_agg(distinct cast(dt as date)) as active_dates
```

把用户活跃日期去重后装入一个数组，例如 `[2026-09-01, 2026-09-05]`。它是日期列表，不是活跃天数；没有显式排序时不要依赖数组的元素顺序。

```sql
filter(p.pay_times, t -> t >= date_add('month', -12, v.start_ts)
                       and t < v.start_ts)
```

`t` 在 `t ->` 处临时定义，代表数组中的每个支付时间；不是源表字段，也不是Python类或装饰器。可以改叫 `pay_time`，含义不变。`filter` 留下符合条件的时间，`cardinality` 统计留下多少个元素。

```sql
case when cardinality(filter(p.pay_times,
  t -> t >= date_add('month', -12, v.start_ts) and t < v.start_ts
)) > 0 then 1 else 0 end as before_reward
```

意思是：起点前12个月有支付记录记1，否则记0。没有匹配到支付数组时，这个CASE也会落到ELSE 0。更熟悉的明细聚合写法是：

```sql
max(case
  when r.order_ts >= date_add('month', -12, v.start_ts)
   and r.order_ts < v.start_ts
  then 1 else 0
end) as before_reward
```

两种写法需要配套不同输入：前者使用用户支付时间数组；后者关联原始支付明细并按用户及起点聚合，不能只替换表达式。

## 3. 名单合并与分组标识

```sql
select uid from vip_user
union
select uid from normal_user
```

这是用于过滤流水的去重UID名单，可以不带组别；后续仍从两张分组表分别计算。若这张表要直接作为分组分析样本，则应显式保留 `user_type`。`union`去重，`union all`保留全部输入行，使用前应核对两组是否互斥。

## 4. 按日期加权解决什么问题

```text
普通用户参考率
= Σ（某日期VIP人数 × 该日起点的普通用户打赏率）
  / Σ（有普通用户基线的日期对应VIP人数）
```

这只调整起点日期构成，不调整活跃程度。同一普通用户进入多个起点时，不能把各日期人数相加当作去重人数。

固定给每个普通用户一个起点后，可以直接计算用户级打赏率；但仍需检查筛选后两组的起点日期和活跃分布，不能声称它们必然完全一致。

日期覆盖数、每天最小/最大普通样本数是诊断字段，不是VIP活跃天数。正式业务结果与诊断检查应分开。

## 5. 命名和时间边界

- 虎牙场景里 `anchor` 容易被理解为主播，观察起点建议叫 `start_ts`、`start_date`或`vip_start_date`。
- 前一年：`[date_add('month', -12, start_ts), start_ts)`。
- 后30天：`[start_ts, date_add('day', 30, start_ts))`，30天不是一个自然月。
- 活跃前30天通常按自然日计算，支付窗口按精确时间戳计算，二者应分别注明。
- 只纳入已完整观察30天的用户；分区缺失不等于没有行为。
- 原讨论沿用正金额消费判断；若指标称为礼物打赏，应先核实消费类型，不能擅自更改已有口径。

## 6. 运行前的最小检查

- VIP编号唯一、连续，VIP起点名单非空，普通UID非空。
- 分配后每个普通UID恰好一行，且两组没有UID交集。
- 每个起点的前12个月和后30天均有完整分区覆盖。
- 活跃天数在0至30之间，最终两组均达到同一门槛。
- 打赏人数不超过分母；分母按UID计数，与去重人数一致。
- 比例使用浮点除法，例如 `100.0 * 打赏人数 / nullif(用户数, 0)`。
- 检查两组最终实际活跃均值及起点日期分布，结果只作描述性比较。

英文说明见 [SQL学习笔记.en.md](SQL学习笔记.en.md)。
