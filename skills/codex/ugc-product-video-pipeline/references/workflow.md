# UGC Product Video Workflow

## Two-Stage Process

Stage A: Audit package.

```text
intake -> product constraints -> localized selling points -> compliance notes -> script -> storyboard plan -> image prompts -> video prompts -> review checklist
```

Stage B: Generation package.

```text
storyboard images -> image-to-video clips -> actual last frames -> final cut -> QA report -> run summary
```

Do not start Stage B until the user approves Stage A.

## Task Folder

Use:

```text
<产品名>_带货视频/
├── audit_pack/
│   ├── brief.md
│   ├── product_constraints.json
│   ├── localized_selling_points.md
│   ├── compliance_notes.md
│   ├── script.md
│   ├── storyboard_plan.json
│   ├── image_prompts.json
│   ├── video_prompts.json
│   └── review_checklist.md
└── generation_pack/
    ├── storyboard_images/
    ├── videos_chain/
    ├── actual_last_frames/
    ├── final_cut/
    ├── qa_report.md
    └── run_summary.md
```

## Intake Questions

Ask for:

- Target market.
- Target platform.
- Target consumer profile.
- Aspect ratio.
- Product name.
- Product images.
- Product selling points.
- Restrictions or banned claims.

If the user gives partial info, infer reasonable assumptions but clearly mark them in `brief.md`.

## Approval Gate

Before generation, the user should approve:

- Product visual constraints.
- Selling point interpretation.
- Compliance notes.
- Script.
- Storyboard plan.
- Image/video prompts.

If any product image or claim is missing, do not pretend it is known.
