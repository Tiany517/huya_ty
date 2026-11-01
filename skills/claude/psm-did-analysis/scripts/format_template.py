"""
Format the PSM+DID report template:
  - Apply Heading 1/2 to section headers
  - Set core conclusions to 12pt bold
  - Indent bullet points and sub-items
  - Set image captions and method notes to 9pt
  - Ensure 微软雅黑 on all runs
"""
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
import re

TEMPLATE = r'C:\Users\tiany\.claude\skills\psm-did-analysis\assets\参与活动用户分析报告模板.docx'
OUTPUT = r'C:\Users\tiany\.claude\skills\psm-did-analysis\assets\参与活动用户分析报告模板_格式化.docx'

doc = Document(TEMPLATE)

# ── Helpers ──
def set_font(run, size=Pt(11), bold=None, color=None, name='微软雅黑'):
    """Apply font to a run. If bold is None, keep original."""
    run.font.name = name
    run._element.rPr.rFonts.set(qn('w:eastAsia'), name)
    run.font.size = size
    if bold is not None:
        run.bold = bold
    if color:
        run.font.color.rgb = color

def set_paragraph_spacing(para, before=0, after=0, line=None):
    """Set paragraph spacing in Pt."""
    pf = para.paragraph_format
    if before: pf.space_before = Pt(before)
    if after: pf.space_after = Pt(after)
    if line: pf.line_spacing = Pt(line)

def indent_paragraph(para, left_chars=2):
    """Indent paragraph by character count (1 char ≈ 0.5 inch at 11pt)."""
    para.paragraph_format.left_indent = Inches(left_chars * 0.21)

def ensure_font_on_all_runs(para, size=Pt(11)):
    """Make sure all runs in a paragraph have 微软雅黑."""
    for r in para.runs:
        if not r.font.name:
            set_font(r, size=size)

# ── Process each paragraph ──
for i, p in enumerate(doc.paragraphs):
    text = p.text.strip()
    if not text:
        continue

    # ── Title (line 0) ──
    if i == 0 and ('PSM+DID' in text or '参与活动' in text):
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        for r in p.runs:
            set_font(r, size=Pt(18), bold=True)
        set_paragraph_spacing(p, before=0, after=12)
        continue

    # ── 结论 (line ~1) ──
    if text.startswith('结论') and len(text) < 10:
        for r in p.runs:
            set_font(r, size=Pt(14), bold=True)
        set_paragraph_spacing(p, before=12, after=6)
        continue

    # ── 结论正文 (the long conclusion paragraph) ──
    if '可以正向拉动' in text or '在付费维度' in text:
        for r in p.runs:
            set_font(r, size=Pt(12))
        set_paragraph_spacing(p, before=0, after=10)
        continue

    # ── Section headers: 一、二、三、etc ──
    if re.match(r'^[一二三四五六]、', text):
        for r in p.runs:
            set_font(r, size=Pt(16), bold=True, color=RGBColor(0x1F, 0x4E, 0x79))
        set_paragraph_spacing(p, before=18, after=8)
        continue

    # ── Sub-headers: 实验活动效果评估方案 ──
    if text == '实验活动效果评估方案':
        for r in p.runs:
            set_font(r, size=Pt(14), bold=True, color=RGBColor(0x2E, 0x75, 0xB6))
        set_paragraph_spacing(p, before=14, after=6)
        continue

    # ── Sub-group labels: 【全量分析】/ 【Dota2兴趣子组分析】──
    if text.startswith('【') and text.endswith('】'):
        for r in p.runs:
            set_font(r, size=Pt(13), bold=True)
        set_paragraph_spacing(p, before=10, after=4)
        continue

    # ── Group definitions (实验组/对照组/分析周期/核心目标) ──
    if text.startswith(('实验组：', '对照组：', 'Dota2兴趣用户定义：', '分析周期：', '核心目标：')):
        for r in p.runs:
            set_font(r, size=Pt(11))
        indent_paragraph(p, left_chars=2)
        set_paragraph_spacing(p, before=1, after=1)
        continue

    # ── "匹配质量说明（结果可信依据）" → sub-header ──
    if '匹配质量说明' in text:
        for r in p.runs:
            set_font(r, size=Pt(14), bold=True, color=RGBColor(0x2E, 0x75, 0xB6))
        set_paragraph_spacing(p, before=14, after=6)
        continue

    # ── PSM method intro (starts with "本次分析通过") ──
    if text.startswith('本次分析通过') or text.startswith('再结合双重差分'):
        for r in p.runs:
            set_font(r, size=Pt(11))
        set_paragraph_spacing(p, before=2, after=2)
        continue

    # ── Numbered quality points: "1.实现精准匹配" / "2.匹配后" / "3.倾向得分" ──
    if re.match(r'^\d\.', text):
        for r in p.runs:
            set_font(r, size=Pt(11))
        indent_paragraph(p, left_chars=1)
        set_paragraph_spacing(p, before=2, after=2)
        continue

    # ── Image caption: 注：treatment为... ──
    if text.startswith('注：treatment为'):
        for r in p.runs:
            set_font(r, size=Pt(9), color=RGBColor(0x80, 0x80, 0x80))
        set_paragraph_spacing(p, before=4, after=4)
        continue

    # ── "关键效果指标（...）" → sub-header ──
    if '关键效果指标' in text and '）' in text:
        for r in p.runs:
            set_font(r, size=Pt(14), bold=True, color=RGBColor(0x2E, 0x75, 0xB6))
        set_paragraph_spacing(p, before=14, after=6)
        continue

    # ── DID核心结论 ──
    if text.startswith('DID核心结论：'):
        for r in p.runs:
            set_font(r, size=Pt(12), bold=True)
        set_paragraph_spacing(p, before=8, after=6)
        continue

    # ── Sub-section headers: "主要正向作用" / "显著负向指标" / "无任何显著负向指标" ──
    if text.startswith(('主要正向作用', '显著负向指标', '无任何显著负向指标')):
        for r in p.runs:
            set_font(r, size=Pt(12), bold=True)
        set_paragraph_spacing(p, before=10, after=4)
        continue

    # ── Effect bullets (● 开头) ──
    if text.startswith('●'):
        for r in p.runs:
            set_font(r, size=Pt(11))
        indent_paragraph(p, left_chars=2)
        set_paragraph_spacing(p, before=1, after=1)
        continue

    # ── Method notes: 注: 净效应对... ──
    if text.startswith('注:') or text.startswith('注：'):
        for r in p.runs:
            set_font(r, size=Pt(9), color=RGBColor(0x80, 0x80, 0x80))
        set_paragraph_spacing(p, before=8, after=4)
        continue

    # ── Default: ensure font ──
    ensure_font_on_all_runs(p, size=Pt(11))

# ── Save ──
doc.save(OUTPUT)
print(f"✅ 格式化完成: {OUTPUT}")
