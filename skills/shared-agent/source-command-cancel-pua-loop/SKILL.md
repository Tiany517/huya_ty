---
name: "source-command-cancel-pua-loop"
description: "取消当前活跃的 PUA Loop（原子级联：state + worktree + 记录）。/pua:cancel-pua-loop。Triggers on: '/pua:cancel-pua-loop', 'cancel pua loop', '取消 pua 循环', '停掉 loop'."
---

# source-command-cancel-pua-loop

Use this skill when the user asks to run the migrated source command `cancel-pua-loop`.

## Command Template

# Cancel PUA Loop — 原子级联取消

v3 语义：不只是删 state，还要清理相关资源、记录 teardown 事件。保证幂等。

## 执行步骤

1. **扫描所有可能的 loop state**：
   ```bash
   mkdir -p "$HOME/.Codex/pua"
   LOOP_FILES=$(find "$HOME/.Codex/pua/" -name "loop-*.md" 2>/dev/null)
   LEGACY_FILE=""
   test -f .Codex/pua-loop.local.md && LEGACY_FILE=".Codex/pua-loop.local.md"
   ```

2. **若全部为空**：
   > No active PUA loop found.

3. **若存在**：
   - 对每个文件读一下 iteration（grep `^iteration:`）
   - 删除文件：
     ```bash
     find "$HOME/.Codex/pua/" -name "loop-*.md" -delete 2>/dev/null
     rm -f .Codex/pua-loop.local.md 2>/dev/null
     ```
   - 清 active-agents 记录：
     ```bash
     rm -f "$HOME/.Codex/pua/active-agents.json" 2>/dev/null
     ```
   - 记录取消事件：
     ```bash
     echo "{\"event\":\"loop_cancelled\",\"iteration_at_cancel\":<N>,\"ts\":\"$(date -u +%FT%TZ)\"}" \
       >> "$HOME/.Codex/pua/teardown.jsonl"
     ```

4. **输出报告**：

   ```
   > [PUA CANCEL] Loop cancelled:
   >   - loop-<session>.md (was at iteration N)
   >   - active-agents.json cleared
   > 已落盘到 ~/.Codex/pua/teardown.jsonl
   ```

## 设计原则

- **原子性**：要么全清要么不动，不允许"删了 state 但漏了 active-agents"
- **幂等性**：重复执行无副作用（rm -f / find -delete 对不存在的路径不报错）
- **可观测**：所有取消事件落盘 teardown.jsonl，便于复盘

## 与其他命令对比

| 命令 | 停 loop | 清 worktree | 清 config | 场景 |
|------|---------|------------|----------|------|
| `/pua:cancel-pua-loop` | ✅ | ❌ | ❌ | 单次刹车 |
| `/pua:off` | ✅ | ❌ | ✅ | 下班 |
| `/pua:teardown-all` | ✅ | ✅ | ❌ | 彻底收工 |
| `/pua:reap-orphans` | 仅 stale | ❌ | ❌ | 定期保洁 |
