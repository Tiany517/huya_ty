# 因果推断手册校验

总体状态：`verified_with_production_caveats`

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| 五个源文件大小和 SHA-256 一致 | PASS | 5 项；仓库异常=[] |
| 仓库副本可追溯到本机原文件 | PASS | 本机匹配异常=[] |
| Markdown 主文档结构可读 | PASS | 行数=2025; 代码块=74; 围栏标记=148; 成对=True; 字符=56721 |
| 第零部分完整包含于优化版 Markdown | PASS | 规范化文本包含=True |
| DOCX 可读且核心主题齐全 | PASS | 段落=871; 表格=4; 字符=31016 |
| HTML 可读且核心主题齐全 | PASS | 可见字符=53107 |
| PDF 页数和正文提取正常 | PASS | 页数=155; 可提取字符=55958 |
| PSM 与 SCM 核心主题覆盖 | PASS | 缺失=[] |
| 11 项中英文方法风险清单一致 | PASS | 英文=11; 中文=11; 英文字段宽度=[6]; 中文字段宽度=[6]; 编号一致=True |
| 关键方法限制均有书面证据 | PASS | 覆盖={'balance heuristic': True, 'paired inference': True, 'control replacement': True, 'common support': True, 'SCM placebo': True} |
| 未发现明文凭据或 .env | PASS | 提取正文命中=0; 路径命中=[]; env=[] |
| 中英文项目文档齐全 | PASS | 缺失=[] |

结论：五个源文件、四种格式、第零部分包含关系和 11 项中英文方法风险已验证。材料只用于教学与代码脚手架，示例结果不是业务因果结论。
