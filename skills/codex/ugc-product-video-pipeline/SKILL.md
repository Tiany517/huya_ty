---
name: ugc-product-video-pipeline
description: Build audit-first AI UGC product-selling video packages and, after approval, generate 9:16 product videos with storyboard images, image-to-video, actual-last-frame chaining, subtitles, BGM, and QA. Use this skill whenever the user mentions 带货视频, AI带货, UGC广告, TikTok product video, product demo video, 多国家多语言卖货视频, product images to video, Seedance/SeeDance图生视频 for products, or wants Codex to create product-selling scripts/prompts/videos. Trigger even if the user only says “帮我做一条带货视频” or “这个产品跑一个墨西哥西语视频”.
---

# UGC Product Video Pipeline

Use this skill to create controlled, multilingual product-selling UGC videos. The default mode is audit-first: produce a reviewable package before spending API quota on image or video generation.

The pipeline reuses the historical-video media lessons:

```text
brief -> product constraints -> localized script -> storyboard plan -> image prompts -> storyboard images -> automatic storyboard QA -> actual-last-frame chained videos -> final cut -> QA
```

## Core Principle

Do not jump directly into video generation. Product videos have higher rewrite cost than historical videos because product appearance, claim accuracy, language localization, and buyer trust all matter. Generate an audit package first. The agent must automatically inspect storyboard outputs and reject failed frames before any video call. User review is optional feedback, not the only quality gate.

## Required Intake

At the start, ask for missing fields. Do not ask all questions if the user already supplied enough information.

Required fields:

- `target_market`: country/region, e.g. China mainland, United States, Mexico.
- `target_platform`: TikTok, Reels, Shorts, Douyin, Xiaohongshu, etc.
- `target_consumer_profile`: age, gender if relevant, household/job context, core pain.
- `aspect_ratio`: default `9:16`.
- `product_name`.
- `product_images`: minimum 1, recommended 2-4.
- `user_provided_selling_points`.
- `restrictions_or_banned_claims`: optional; if absent, infer compliance risks.

When product images are missing, ask the user to attach them before writing image/video prompts. You may draft the script and brief without images, but mark product visual constraints as incomplete.

## Supported Market Packs

Version 1 defaults:

- Chinese: China mainland short-video commerce style.
- English: US/TikTok UGC style.
- Mexican Spanish: Mexico/TikTok UGC style.

For other markets, use custom localization and clearly say the localization is less deeply calibrated unless the user provides examples.

Do not mechanically translate. Rewrite for the local market.

## Audit Package

Create a task folder:

```text
<project-root>/<产品名>_带货视频/
├── audit_pack/
└── generation_pack/
```

Before generation, create these files under `audit_pack/`:

- `brief.md`: user input, inferred assumptions, missing info.
- `product_constraints.json`: visual constraints from product images.
- `localized_selling_points.md`: selling points separated by market/language.
- `compliance_notes.md`: risky claims, unsupported claims, forbidden wording.
- `script.md`: localized UGC script.
- `storyboard_plan.json`: beat-level storyboard plan.
- `image_prompts.json`: storyboard image prompts.
- `video_prompts.json`: video generation prompts.
- `review_checklist.md`: what the user must approve before generation.

Use templates from `templates/` when creating these files.

## Product Visual Constraints

The `product_constraints.json` file is central. All image and video prompts should inherit it.

Lock:

- Product color.
- Shape and silhouette.
- Size relative to hand, face, sink, table, or other objects.
- Material and texture.
- Logo/label placement if visible.
- Buttons, ports, nozzles, attachments, screens, or moving parts.
- Installation/use state.
- Allowed transformations.
- Forbidden transformations.
- Required product visibility per scene.

Separate observations from assumptions. Do not invent a feature just because it would sell well.

## Selling Point Rules

Separate claims into:

- `user_provided`: explicitly provided by the user.
- `visual_or_demonstrable`: can be shown in the video.
- `inferred_suggestion`: Codex-generated angle, needs user approval.
- `risky_or_unsupported`: should not be used unless the user provides proof.

Prefer selling points that can be demonstrated on camera.

Avoid:

- Medical claims.
- Fake certifications.
- Fake prices or discounts.
- Unsupported performance guarantees.
- “Best”, “official”, “100%”, “cures”, “guaranteed” unless evidence is provided.

## Default Script Structure

Default video length: 15-30 seconds.

Default beat structure:

1. 0-3s: pain point / hook.
2. 3-7s: product reveal.
3. 7-18s: function demo.
4. 18-25s: result / reason to buy.
5. 25-30s: soft CTA.

Adjust duration based on script density. Do not force every segment to 5 seconds.

## Language Style

Chinese:

- Short, direct, conversion-oriented.
- Natural spoken style, not formal ad copy.
- Suitable for Douyin/Xiaohongshu unless the platform says otherwise.

English:

- Conversational TikTok UGC.
- Natural first-person or creator-style phrasing.
- Avoid over-polished infomercial tone.

Mexican Spanish:

- Natural Mexican Spanish.
- Conversational, everyday phrasing.
- Avoid literal translation and Spain-specific wording.

## Storyboard And Prompt Rules

Each storyboard beat should define:

- Scene.
- Creator/person identity.
- Product state.
- Action.
- Camera framing.
- Spoken line.
- On-screen post-production text, if any.
- Product consistency constraints.

Each storyboard beat must also declare its `reference_strategy`:

- `canonical_product_refs`: the original product photos that define non-negotiable silhouette, material, scale, and installation details.
- `scene_anchor_ref`: the approved kitchen, room, or background anchor for that scene.
- `presenter_anchor_ref`: an approved presenter image when a face appears; omit it and use hands-only framing when unavailable.
- `previous_shot_ref`: the immediately preceding approved storyboard image, used only for a continuous camera move in the same scene.
- `inheritance_mode`: `none`, `soft`, or `strict`.

Use references deliberately:

- `strict`: same room, same person, same product state, and a continuous action. Supply the previous approved frame plus canonical product and presenter/scene anchors.
- `soft`: same product or room but a new angle. Supply canonical product and relevant scene/presenter anchors; use the previous frame only as a visual-style reference.
- `none`: a deliberate scene change. Do not inherit the prior frame; reset to canonical anchors.

Never use only a previous generated image as the product reference. It can propagate a small model error through the entire sequence. Original product references always outrank generated frames. Reference chains may only use a frame that has passed storyboard QA.

Image prompts should generate clean storyboard frames without text. Video prompts should ask for voice and mouth movement together.

Do not ask image or video models to render titles, subtitles, price cards, or labels. Add those in post-production.

For products whose installation geometry matters, first generate and approve an `installation_reference_frame`: a close-up image that proves the exact product is physically attached to the correct object. Derive all installed/use shots from this approved reference, rather than asking the model to independently recreate the installation in every shot.

If a fixed presenter reference image is unavailable, do not generate a face-led multi-shot presenter sequence. Prefer hands-only POV, over-the-shoulder, or product-led shots. A target-market descriptor alone does not guarantee the same identity across independently generated images.

## Automatic Storyboard Quality Gate

This gate is mandatory. The agent owns the decision; do not send visibly failed storyboard frames to video generation or ask the user to approve obvious defects.

After each image batch:

1. Save every image under `generation_pack/storyboard_images/` with deterministic names and create a contact sheet.
2. Inspect every frame individually and the contact sheet as a sequence.
3. Record `generation_pack/storyboard_qa.json` with a pass/fail decision, reasons, and retry count for each frame.
4. Reject and regenerate only the failed frames. Do not delete earlier outputs; place rejected variants in a versioned/rejected folder or retain them with a rejected status.
5. Do not submit a video task until all required frames pass.

Hard rejection criteria:

- The product looks composited, illustrated, plastic-CG, or pasted into a photographic scene.
- Product silhouette, color, parts, material, or internal structure differs from the reference images.
- Product scale is implausible. For a faucet attachment, it must remain palm-sized and must not exceed the faucet arch or hand by an implausible factor.
- The product is floating, clipped into the faucet, mounted to the wrong part, has impossible plumbing, or cannot physically route water.
- A reference-dependent presenter changes identity, age, clothing, ethnicity/market fit, or kitchen between connected shots.
- The requested action cannot be clearly understood from the image.
- Any frame contains model-rendered titles, subtitles, watermarks, fabricated branding, certificates, or unsupported claim graphics.

For faucet-mounted products, prompts must explicitly state: attach the adapter to the faucet outlet/nozzle, keep the faucet body separate and visible, make the filter chamber hang below the outlet, use a physically continuous water path, preserve realistic gravity and scale, and never place the device beside, in front of, or floating below the faucet.

Fail closed: if the model cannot preserve a product after two targeted retries, switch strategy before continuing. Use a real installed product image as the base/reference, reduce the shot to product-only or hands-only, or request a better real installation reference from the user. Never spend video quota on a failed storyboard set.

## Video Generation Strategy

For audit packages, write prompts and JSON first. When the user authorizes generation, call image APIs in small batches, run the automatic storyboard quality gate, and only then call video APIs. Do not treat user approval as a substitute for the quality gate.

For generation:

- Draft mode can use storyboard-pair generation.
- Final mode should use actual-last-frame chaining by default.

Actual-last-frame chaining:

```text
segment 1: storyboard 01 -> storyboard 02
extract actual last frame from segment 1
segment 2: actual last frame 01 -> storyboard 03
extract actual last frame from segment 2
```

This is slower but improves continuity of person, room, product, hands, and camera angle.

Actual-last-frame chaining does not by itself preserve a detailed physical product. Generate one segment at a time. After each segment, extract and inspect an early, middle, and terminal frame. Record the result in `generation_pack/video_segment_qa.json`. Submit the next segment only if the previous segment passes shape, scale, attachment, audio, and black-frame checks. If it fails, its extracted terminal frame is forbidden as a next-segment input.

Prompt each segment to:

- Continue from the previous shot.
- Keep the same person, outfit, room, product, lighting, and camera style.
- Keep the product the same size and shape.
- Generate natural target-language speech with mouth movement.
- Avoid clip-level BGM.
- Avoid subtitles, titles, watermark, black screen, fade, flash, and transition effects.
- Hold the final frame stable for 0.3-0.5 seconds when chaining.

## Post-Production

Post-production owns:

- Title.
- Subtitles.
- BGM.
- Price/offer card when approved.
- CTA text when approved.
- Crop/fill.
- QA frames.

Reuse the proven visual style when appropriate:

- Large white title with black outline near top third.
- Yellow subtitles with black outline, max two lines.
- Safe margins so subtitles do not overflow.

Use one continuous BGM track in post. Ask the video model for speech plus light environmental sound, not per-clip music.

Final render rules:

- Hard concat.
- No `xfade`.
- No `fadeblack`.
- No `pad`.
- No black cards.
- No narration `acrossfade`.

For 9:16 output:

```text
scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1
```

## QA

Before delivering final video:

- Run `ffprobe` for codec, duration, resolution, aspect ratio.
- Run `blackdetect`.
- Extract first, middle, end, and segment-boundary frames.
- Inspect product consistency.
- Inspect subtitle size and position.
- Check that narration is not clipped.
- Check BGM does not end at an awkward climax.
- Check no unsupported claims appear in subtitles/title/CTA.

Before video generation:

- Confirm `storyboard_qa.json` marks every required frame as passed.
- Confirm an approved installation reference exists for products requiring physical installation.
- Confirm every source image, generated image, clip, extracted terminal frame, and QA artifact is saved locally in the task folder.

Report residual risks if the final video was not watched end-to-end.

## Reusable Scripts

Use bundled scripts as starting points:

- `scripts/generate_huya_story_media.py`: Huya image/video generation.
- `scripts/generate_huya_chained_story_videos.py`: actual-last-frame chained generation.
- `scripts/resume_huya_chained_task.py`: recover already-submitted tasks.
- `scripts/render_caocao_chain_v2_final.py`: renderer template to generalize for product videos.

The renderer template is historical-name-specific; rename variables and paths before using it for products.

## References

Read these as needed:

- `references/workflow.md`: detailed audit/generation package structure.
- `references/localization.md`: market/language rules.
- `references/product_consistency.md`: product visual constraint rules.
- `references/compliance.md`: claim safety rules.
- `references/postproduction_qa.md`: subtitles, BGM, concat, QA.

## Final Response Contract

When finishing an audit package, report:

- Audit package path.
- Missing fields, if any.
- Target market/platform/language.
- Script duration estimate.
- Whether generation is blocked pending approval.

When finishing a generated video, report:

- Final video path.
- Whether actual-last-frame chaining was used.
- Model(s) used.
- Duration, resolution, aspect ratio.
- Black frame check result.
- Product consistency risks.
- Localization/compliance risks.
