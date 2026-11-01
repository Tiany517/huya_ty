---
name: imbot-cli
description: 微信/企微 IM 机器人 CLI，通过 wkteam/QiWeAPI 管理联系人、群聊和收发消息，除非用户明确要求发微信/企微消息，否则不要使用本SKILL
---

# imbot-cli 使用指南

基于 `imbot-cli` 的微信个人号与企微操作，底层调用 wkteam API（微信）和 QiWeAPI（企微）。

## 安装与更新

```bash
pip install imbot_cli -i https://pypi.huya.info/simple/ --upgrade
```

首次使用或需要更新时执行上述命令，确保为最新版本。

---

## 一、企微 (wecom)

### 2) 发送消息

#### 发送文本

```bash
# 按昵称发送（默认搜索最近 3 小时活跃记录）
imbot-cli wecom send-text --to-name "罗伟滨" --content "hello"

# 扩大搜索范围
imbot-cli wecom send-text --to-name "潘建宁" --content "hello" --hours 72

# 按 user_id 发送
imbot-cli wecom send-text --to-id "1688857177233230" --content "hello"
```

#### 发送超文本（支持 @ 人）

```bash
imbot-cli wecom send-hyper-text \
  --to-id "1688857177233230" \
  --content "请查收" \
  --at-ids "user_id1,user_id2"
```

#### 发送图片

需要先 `upload-file` 获取 `--file-aes-key`、`--file-id`、`--file-md5`。

```bash
imbot-cli wecom send-image \
  --to-id "<user_id>" \
  --file-aes-key "<key>" \
  --file-id "<file_id>" \
  --file-md5 "<md5>" \
  --file-size <bytes> \
  --filename "image.png"
```

#### 上传文件

```bash
imbot-cli wecom upload-file \
  --file-url "https://example.com/image.png" \
  --filename "image.png"
```

### 3) 查找联系人 / 群聊

```bash
# 模糊搜索（昵称或群名）
imbot-cli wecom find --name "潘建宁" --hours 72
```

### 4) 联系人管理

```bash
# 列出所有用户（返回 platform / user_id / nickname / oaid）
imbot-cli wecom list-users
```

### 5) 群聊管理

```bash
# 列出群聊
imbot-cli wecom list-rooms --hours 72

# 创建群聊
imbot-cli wecom create-room \
  --members "1688857177233230,1688858190749361" \
  --name "告警通知群"

# 邀请成员
imbot-cli wecom invite-member \
  --room-id "<room_id>" \
  --members "user_id1,user_id2"

# 修改群名
imbot-cli wecom modify-room-name \
  --room-id "<room_id>" \
  --name "新群名称"
```

### 6) 典型工作流

```
# 发消息给联系人
list-users → send-text --to-id ...   （按 ID 发）
             或 send-text --to-name ... （按昵称，需近期互动）

# 建群并发通知
list-users → create-room --members "..." → send-text --to-id "<room_id>"
```

---

## 二、微信个人号 (wechat)

### 2) 发送消息

```bash
# 按 wcid 发送
imbot-cli wechat send-text --wcid "wxid_xxx" --content "hello"

# 按昵称发送
imbot-cli wechat send-text --to-name "潘建宁" --content "hello" --hours 72

# 支持 @ 人
imbot-cli wechat send-text --wcid "群wcid" --content "通知" --at "wxid_user1,wxid_user2"
```

### 3) 查找联系人 / 群聊

```bash
imbot-cli wechat find --name "潘建宁" --hours 72
```

### 4) 联系人管理

```bash
# 列出所有用户
imbot-cli wechat list-users --hours 72
```

### 5) 群聊管理

```bash
# 列出群聊
imbot-cli wechat list-rooms --hours 72
```

### 6) 典型工作流

```
# 发消息给微信好友
list-users → send-text --wcid "wxid_xxx"   （按 wcid 发）
             或 send-text --to-name "xxx"   （按昵称，需近期互动）

# 查群并发消息
list-rooms → send-text --wcid "<群wcid>" --content "通知"
```

---

## 三、对比速查

| 能力 | 企微 (wecom) | 微信 (wechat) |
|------|:-----------:|:------------:|
| 查用户 | ✅ `list-users` | ✅ `list-users` |
| 查群聊 | ✅ `list-rooms` | ✅ `list-rooms` |
| 搜索 | ✅ `find` | ✅ `find` |
| 发文本 | ✅ `send-text` | ✅ `send-text` |
| 发超文本 | ✅ `send-hyper-text` | ❌ |
| 发图片 | ✅ `send-image` | ❌ |
| 上传文件 | ✅ `upload-file` | ❌ |
| 建群 | ✅ `create-room` | ❌ |
| 邀请入群 | ✅ `invite-member` | ❌ |
| 改群名 | ✅ `modify-room-name` | ❌ |
| @ 人 | ✅ 通过 `--at-ids` | ✅ 通过 `--at` |
| 按昵称发 | ✅ `--to-name` | ✅ `--to-name` |
