# AI Gift Manual Tagging Rules (v6 frozen)

Scope: manual relabeling of all 5,592 rows in `AI工坊被送出的礼物明细`.

Period: 2026-07-13 through 2026-09-14. Amount means the gift's tipping amount during this window, in CNY.

## 1. Decision principles

1. A human reviewer must read the gift name, user prompt, and primary/secondary/third streamer fields row by row. Keyword rules must not make the final decision automatically.
2. Scripts may only queue rows, fetch data, cross-check same-room and whole-table name occurrences, write labels back, and calculate summaries.
3. Cross-check results are evidence, not the decision. The reviewer must read the source row before assigning a label.
4. If the meaning remains unclear, label the row `存疑` (uncertain) and state what is unclear. Do not guess.

## 2. Frozen primary and secondary vocabularies

Do not add categories.

| Primary category | Allowed secondary categories |
| --- | --- |
| 主播IP / Streamer IP | 主播肖像 / 主播热梗 / 公会肖像 / 网友热梗 |
| 女性角色 / Female character | 可爱 / 炫酷 / 国风 / 明星 / 其他 |
| 男性角色 / Male character | 可爱 / 炫酷 / 国风 / 明星 / 其他 |
| 动物 / Animal | 动物 |
| CP / Pairing | CP |
| 文字互动 / Text interaction | 文字互动 |
| 场景与氛围 / Scene and mood | 其他 / 婚礼 / 国风 / 嘉年华 / 玫瑰 / 夕阳 / 阳光 / 城堡 / 烟花 / 金钱雨 / 流星雨 / 520 / 猫粮 / 虎牙一号 / 抽奖池 / 植被 / 太阳 / 过山车 / 欢呼 |
| 诙谐低俗 / Humorous or vulgar | 诙谐低俗 |
| 游戏/动漫角色 / Game or anime character | 游戏/动漫角色 |
| 美食饮品 / Food and drink | 食品/饮品 |
| 豪车载具 / Luxury vehicle | 豪车载具 |
| 道具 / Prop | 道具 |
| 庆生与祝福 / Birthday and blessing | 庆生与祝福 |
| 神话角色 / Mythological character | 神话角色 |
| 生活用品 / Daily item | 生活用品 |
| 惊悚 / Horror | 惊悚 |
| 其他 / Other | 其他 |

Position values: 主主播 (primary streamer), 第二主播 (second streamer), 第三主播 (third streamer), 非本行主播 (streamer outside the current row), 圈层 (community circle), 待定 (undetermined), or `-`.

## 3. Four secondary categories under Streamer IP

- **Streamer portrait**: the main subject is the streamer, including cartoon or animal forms, or the item contains a signature/identity mark of that streamer. Confirmed examples include `顾小七最美`, `毛神加油`, `爱汐`, and `柒宝生日快乐`.
- **Streamer meme**: a phrase, catchphrase, room number, or room-specific number created by the streamer's room. Examples include 99101, 锤宝, 泽泽, 秋秋, 劳帕, 梦勋, 挖掘机, 折耳根, 扫雪, and 正龟军.
- **Guild portrait**: a guild, circle, or clan mark. Examples include 仙女传媒, 集美233, 八门, 黄门, 娜家军, 虎家军, and 渣皇团.
- **Viewer meme**: a platform meme or an identity of a major tipper that appears across rooms. Examples include 陌白, 时倾, 帝临, 聋瞎, 阿初, and 虎牙7号. Major-tipper names do not receive a separate secondary category and remain under Viewer meme.

Decision order: first test whether the visual is the streamer or carries the streamer's name; then whether it is unique to that room; then whether it is a guild/circle mark; only then assign Viewer meme.

## 4. Four recurring errors to exclude row by row

1. **Character coincidence**: a subject character matches a character in the streamer's name but has no relationship to the streamer.
   - Counterexample: `梧桐之恋` or `凤栖梧桐` versus a streamer named 桐桐 is Scene and mood, not Streamer IP.
   - Counterexample: `麦田少女` versus 麦麦 is Female character, not Streamer IP.
   - Counterexample: `鲜衣怒马` versus a name containing 怒 is Male character; the shared character alone is insufficient.
   - Confirmed positive examples: 锤宝 for 大锤酱, 泽泽 for 严君泽, 秋秋 for 瑞秋儿, and 圈圈 for 甜甜圈 are Streamer memes.
   - Test: does the shared character carry a pun, substitution, or central meaning in the name? If yes, it can be Streamer IP. If it is only the same character, tag by subject.
2. **Name from another room**: when a prompt contains a name absent from the row's three streamers, search for the same name in other rows.
   - If occurrences concentrate in one circle, it may be Streamer IP / Viewer meme with position `圈层` or `非本行主播`.
   - If it appears once and the meaning remains unclear, retain the literal subject category and add `存疑`; do not force it into Streamer IP.
3. **Anthropomorphic subject**: classify an object, food, or animal by its subject even if the art style is comedic.
   - Food ingredients such as chestnut, mushroom, preserved egg, and strawberry go to Food and drink.
   - Objects such as a spinning top, ring, magic book, trophy, or mechanical object go to Prop.
   - Animals go to Animal.
4. **Suggestive or comedic content**: suggestive, vulgar, self-deprecating, or deliberately silly subjects such as baldness, feces, leg hair, slaps, or comic ugliness go to Humorous or vulgar, not Female or Male character.

## 5. Confirmed room and circle terms

These terms support cross-checking and remain valid when later additions follow the same evidence standard.

| Term | Attribution | Evidence |
| --- | --- | --- |
| 八爷 | 猫儿2斯诺克 room | 9 total occurrences; 8 in that room, using the 大橘 + 小喇叭 image |
| 黄门 / 八门 | 798 circle | 4 黄门 and 3 八门 items across 软妹, 壮壮, 大锤酱, 张开朗, and other 798 rooms |
| 娜家军 | 娜娜大王798 fan group | 4 items, including `娜家军牛逼` |
| 虎家军 | 虎子【1995】 fan group | Contains `虎家军牛逼` |
| 正龟军 / 折耳根 / 扫雪 / 泽泽 | Letme严君泽 room | 7 折耳根, 6 turtle, 5 扫雪, and 10 泽泽-series items |
| 白阳 | QY room | 3 items, all in the QY room |
| 劳帕 / 梦勋 / 孟勋 / 康康 / 牢帕 | 神枪小子 room | 33 fallback-queue items in the room |
| 挖掘机 | 狂鸟丶楚河-90327 room | 11 excavator-type items, mostly in that room |
| 蛋肯 | DANK1NG | 2 items, both puns on the streamer name |
| 茶冻 | 龙爪茶冻【AJ】 | 6 items, including `茶冻帮桂霞` |
| 99101 | 十一【AJ】【518】 room | 2 items, both in that room |
| 锤宝 / 八（798） | 大锤酱798 room | 3 `给锤宝亿点甜` items |

## 6. Output format

Write one UTF-8 tab-separated file per batch, with no repeated header rows:

```text
gift_id	gift_name	primary_category	secondary_category	position	rationale
```

- Primary and secondary values must come from Section 2.
- Every non-Streamer-IP row uses `-` for position.
- The rationale should state the visual subject and the attribution evidence in one sentence.
- Every uncertain row must contain `存疑` in the rationale.
- File naming: `人工标注_<queue-name>_batch<two-digit-number>.tsv`.

## 7. Calibration sample

The 200-row calibration set consists of:

- `人工标注_兜底_batch05.tsv`: fallback rows 441-540, 100 rows, including 13 uncertain labels.
- `人工标注_单字_batch01.tsv`: single-character-match rows 1-100, 100 rows, including 25 uncertain labels.

After each new 100 rows, compare the primary-category distribution with the adjacent calibration sample. If one category shifts by more than 10 percentage points, stop and review the decision rule before continuing.

## 8. Confirmed additions from the 2026-09-21 whole-table cross-check

| Term | Attribution | Evidence |
| --- | --- | --- |
| 猫爷 / 大橘 / 小喇叭 | 猫儿2斯诺克 room | 猫爷 appears 7/7 there; most 大橘 images are in the room |
| 八爷 (大橘 + 小喇叭 image) | 猫儿2斯诺克 room | 20 of 25 occurrences are in the room |
| 蛋肯 / 蛋啃 / 蛋神 | DANK1NG | Name puns, every occurrence in the room |
| 康康 / 康神 | 神枪小子 room | Same rule as 劳帕/梦勋; position follows the streamer slot |
| 劳帕 / 牢帕 / 梦勋 / 孟勋 | 神枪小子 room | 33 fallback-queue items in the room |
| 挖掘机 / 原谅兽 | 狂鸟丶楚河-90327 | 3/3 each |
| 扫雪 / 折耳根 / 正龟 / 泽泽 / 摄影道理 / 天津 / 邯郸 / 玄武吐奶 / 梅花鹿 | Letme严君泽 | 梅花鹿 appears 7/8 in the room |
| 茶冻 | 龙爪茶冻【AJ】 | Includes `茶冻帮桂霞` |
| 白阳 | QY room | 3 items |
| 茄子王 / 维小宝 / 几粒 | LK-万里挑一 | 茄子 appears 12/18 in the room |
| 锦禾 | Qr-桃之夭夭 | 2/2, including `锦禾徽章` |
| 姜早 | CUTE-头号可爱 | 2/2 |
| 榕帝 | 瑞秋儿【能心】 | 3/3, including `给榕帝请安` |
| 夏美 | 星晴-全是美女 | 13/13 |
| 豪猪 | 陈子豪 | 3/3 |
| 赵果果 | 天选-日月倾城 | 3/3 |
| 崩哥 | 老实人sask | 2/2 |
| 杨海燕 | 杨漾打小就行 | 2/2 |
| 李逵 | 乐佰、小白 | 6/7 |
| 忍君子 | 狂魔哥解说 | 2/2 |
| 马头 | kRYST4L / 老实人sask circle | 8/10 |
| 牛棚 / 文哥 / 锤宝 | 大锤酱798 | See Section 5 |
| 16028 | circle channel number | Used by 丫头【16028】 and 小杨【16028】 |
| 八门 / 黄门 / 渣皇团 / 娜家军 / 虎家军 / 刷刷刷 / 魔木系 / 御天苍龙 | 798 and other circles | Repeated across rooms |

## 9. Hard constraints approved on 2026-09-21

1. A glowing `八` character, or a banner consisting only of that character, is not Streamer IP. Use `文字互动/文字互动/-`. Corrected examples: `八耀金辉`, `八字生辉`, and `八福临门`.
2. If the prompt or visual contains only a guild mark such as 八门 or 黄门, assign `主播IP/公会肖像/圈层`. Use the primary-streamer position only when the visual is the guild leader or carries that person's signature.
3. **Birthday and celebration priority**: if the visual theme is a birthday, anniversary, or blessing, including cake, party hat, or greeting text, use `庆生与祝福/庆生与祝福` even if the image also uses a room-specific character. Examples: `红鼠寿星`, `红鼠庆生`, `赖皮寿星`, `月兔送福`, and `牧羊甜心`.
4. **Room-motif consistency**: a room-specific animal or named character belongs to Streamer IP. Position follows the streamer slot on that row: primary streamer, second streamer, streamer outside the row, or circle. Examples include the 大橘 + 小喇叭 / 八爷 / 猫爷 motif for 猫儿2斯诺克; 红鼠 for 盛世-伯千; 小白熊/熊粮 for 不命苦的白熊; 小毛驴 for 驴鸽LvGe; 大猩猩 for 抱抱-798; 猩猩公主 for 公主HAP; 来福/康康/梦勋 for 神枪小子; 蛋肯 for DANK1NG; 八洋宝贝 for LK-万里挑一; 梅花鹿/折耳根/扫雪/泽泽 for Letme严君泽; 李逵 for 乐佰小白; and 茶冻 for 龙爪茶冻. The detailed corrections are in `人工打标/母题一致性改判明细.tsv`, which is not included in this repository.

Chinese source: `gift-tagging-rules-v6-frozen.md`.
