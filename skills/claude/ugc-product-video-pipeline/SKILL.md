---
name: ugc-product-video-pipeline
description: Build audit-first AI UGC product-selling video packages and, after approval, generate 9:16 product videos with storyboard images, image-to-video, actual-last-frame chaining, subtitles, BGM, and QA. Use this skill whenever the user mentions 带货视频, AI带货, UGC广告, TikTok product video, product demo video, 多国家多语言卖货视频, product images to video, Seedance/SeeDance图生视频 for products, or wants Codex to create product-selling scripts/prompts/videos. Trigger even if the user only says “帮我做一条带货视频” or “这个产品跑一个墨西哥西语视频”.
---

# UGC Product Video Pipeline

Use this skill to create controlled, multilingual product-selling UGC videos. The default mode is audit-first: produce a reviewable package before spending API quota on image or video generation.

The pipeline reuses the historical-video media lessons:

```text
intake -> product structure recognition -> stable asset manifest -> brief -> product constraints -> localized script -> storyboard plan -> image prompts -> storyboard images -> automatic storyboard QA -> actual-last-frame chained videos -> final cut -> QA
```

产品结构识别和素材登记是生成前置门禁，不得跳过。

## Core Principle

Do not jump directly into video generation. Product videos have higher rewrite cost than historical videos because product appearance, claim accuracy, language localization, and buyer trust all matter. Generate an audit package first. The agent must automatically inspect storyboard outputs and reject failed frames before any video call. User review is optional feedback, not the only quality gate.

## Product Structure Recognition Gate

Before writing storyboard prompts or calling any image/video API, inspect the supplied product images and create two artifacts:

- `usage`: correct operation facts, operating controls, installation-only parts, ordered usage steps, effects, safety limits, and forbidden interactions.
- `asset_manifest.json`: stable asset IDs and roles for canonical product views, installation anchors, scene/presenter anchors, approved storyboard frames, and actual-last frames.

The recognition result must be `recognition.status=passed`. Do not infer unobserved parts, dimensions, certifications, or performance claims. A product requiring physical attachment must have an approved installation anchor before generation.

For each product, record the relationship graph, not only adjectives. Record usage as a separate fact layer: identify every operable component, every installation-only component, the allowed action on each control, the state/effect it produces, ordered usage steps, safety limits, and forbidden interactions. Never infer a control from shape alone. If usage recognition is pending, do not generate instructional interaction footage; obtain a real operation reference, specification, or explicit user confirmation first.

For an operation shot, the contract must name `required_interaction_id`, `required_action`, `expected_effect`, and `forbidden_interactions`. The operation component must be visible at a useful scale, spatially isolated from installation-only parts, and unobstructed by the hand during the decisive action. Sampled evidence must show the control before contact, during contact/action, and after the resulting state change; an ambiguous hand near the product is not proof. A hand touching the wrong component is a functional failure even when the product appearance and installation are correct.

Use stable asset IDs rather than filenames as the primary references. A generated frame may inherit continuity, but it never becomes a canonical product source. If structure remains uncertain after two targeted recognition attempts, stop generation and switch to real-image montage, hands-only shots, or request a better reference.

## Camera Keyword Vocabulary

Storyboard prompts must use a controlled camera vocabulary. Each shot should specify `camera_effect`, `camera_keywords`, `camera_subject`, `camera_amplitude`, and `camera_duration`; do not rely on vague wording such as “自然移动”. Supported mappings:

| Effect | Chinese keywords | Constraint |
|---|---|---|
| Push in | 推镜头 / 缓慢推进 / 急速推进 | State start/end framing and keep product geometry fixed. |
| Pull out | 拉镜头 / 逐渐拉远 | Do not reveal a changed product or new installation state. |
| Left/right | 左摇 / 右摇 / 横移 | Keep the faucet body and attachment relationship visible. |
| Follow | 跟随镜头 / 跟拍 | Use only when the tracked subject and product remain in one physical scene. |
| Orbit | 环绕镜头 / 360度旋转 | Do not use for a mounted product unless the attachment and water path remain visible throughout. |
| Crane | 升镜头 / 降镜头 / 俯冲 | Avoid hiding the connection point or changing gravity cues. |
| Hitchcock zoom | 希区柯克变焦 / 一镜到底 | Treat as a combined push/pull effect; reject if it conflicts with another zoom or a fixed reference frame. |
| Handheld | 手持晃动 | Set amplitude explicitly; low amplitude only for UGC realism, never enough to obscure structure. |

A shot must choose one primary camera effect. Conflicting effects such as `推镜头 + 拉镜头`, `环绕 + 固定特写`, or `一镜到底 + 跳切` are rejected before submission. Camera motion is subordinate to product structure: no motion may turn a mounted device into a floating, disconnected, or reassembled object.

## Provider Priority And Fallback

Use Huya/海艺 as the preferred image and video provider when the configured model and account quota are available. If Huya returns quota exhaustion or a terminal generation failure, fall back per task to ToAPIs:

- Image fallback options: `gpt-image-2` or `doubao-seedream-5-0` via `POST https://toapis.com/v1/images/generations`. For GPT-Image-2 use top-level `resolution` (`1k`, `2k`, `4k`), `size: "9:16"`, `image_urls` for image-to-image references, and `response_format: "url"`. Query GPT image tasks with `GET https://toapis.com/v1/images/generations/{task_id}` and read the completed image from `result.data[0].url`. For Seedream 5.0 use `model: "doubao-seedream-5-0"`, `image_urls`, `size: "9:16"`, and `metadata.resolution` (`2K` or `3K`). Upload local references first via `POST https://toapis.com/v1/uploads/images`.
- Video fallback: `seedance-2-fast` via `POST https://toapis.com/v1/videos/generations`; in the current ToAPIs deployment, query with `GET https://toapis.com/v1/videos/generations/{task_id}` (a request to `/v1/tasks/videos/{task_id}` returned HTTP 404). Use `image_with_roles` for `first_frame` and `last_frame`. ToAPIs rejects mixing first/last-frame mode with `reference_image` mode, so choose exactly one mode per task: for chained product video segments, use the two approved frame slots and transmit canonical/installation structure through the compiled prompt; only use extra `reference_image` roles when the task is intentionally reference-image mode without first/last frame roles.

Fallback is per task, not a silent provider switch for the whole project. Record provider, model, fallback reason, task ID, reference asset IDs, and result URLs in state/log files. Never write API keys to configs, prompts, state, logs, or output media. ToAPIs reference images must be public URLs; local paths are not valid API inputs.

Provider isolation is mandatory. Each provider must use its own base URL, upload function, task submission function, and polling function; never pass a ToAPIs key to a Huya helper or reuse a Huya upload/cache path in the ToAPIs branch. Before blaming credentials, run an independent multipart upload with the same key and one of the exact local reference files to the provider's upload endpoint. Compare the direct request with the runtime request: URL, Authorization header, multipart field name, purpose field, and response status/body. A direct `200` means the provider upload is available and the runtime routing/request construction must be investigated; a direct `401` isolates the failure to provider-side key validity or upload permission. Do not infer image-upload permission from a successful video query.


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
- An operation control is hidden, too small, merged with an installation part, or covered so the decisive hand contact cannot be identified.
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

Generate one segment at a time. After each segment, save the provider's raw video, extract and inspect early/middle/late frames, and write structured post-generation evidence. The evidence must record the actual observed product state, hand contact, operated component, action, physical path, and functional result; a prompt, API success response, or free-text claim is not evidence. Submit the next segment only if the previous segment passes shape, scale, attachment, interaction, physics, audio, and black-frame checks. If it fails, its extracted terminal frame is forbidden as a next-segment input.

For stateful products, define mutually exclusive output states and the allowed transition between them. A chained segment must not inherit an ambiguous or already-active state when it is supposed to demonstrate switching. If a control changes routing, mode, power, or position, the previous terminal frame must show a known state, the next segment must show the control transition, and the resulting state must be visible. Reject simultaneous mutually exclusive outputs, state jumps without a visible transition, or a segment whose first frame already contradicts the declared starting state.


1. `raw_generation_qa`: preserve and inspect the original downloaded video; record codec, audio, duration, resolution, black frames, sampled frames, and visual findings.
2. `normalized_delivery_qa`: normalize format with the standard scale/crop rule, re-run technical checks, re-extract frames, and re-check visual continuity. Normalization may fix dimensions or codecs; it never overrides a failed product interaction, missing feature, unsafe action, or broken physical path.

A segment is passable only when both the required visual evidence and the required delivery evidence pass. Never mark a clip passed because its prompt was detailed or its provider task completed.

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
- Inspect product consistency, operating component, hand contact, action sequence, and expected effect against the product usage contract.
- Reject any hand operation of an installation-only component, wrong button/knob/port, impossible installation step, or action whose claimed effect is not visible.
- Reject ambiguous control evidence: the required control must be identifiable before, during, and after the decisive action; proximity is not operation proof.
- Treat liquid, gravity, contact, collision, occlusion, power/connection, and attachment continuity as visual evidence checks, not prompt assumptions.
- Keep raw-generation QA and normalized-delivery QA separate; a successful crop cannot repair a wrong action.

Before video generation:

- Confirm `storyboard_qa.json` marks every required frame as passed.
- Confirm an approved installation reference exists for products requiring physical installation.
- Confirm every source image, generated image, clip, extracted terminal frame, and QA artifact is saved locally in the task folder.

## Iteration Loop

For every test product, run the complete loop:

```text
product facts -> audit constraints -> storyboard -> generate -> sample raw video -> inspect -> classify root cause -> update reusable Skill/contract -> regenerate -> re-inspect
```

Classify every failure before changing anything:

| Failure class | Typical symptom | Reusable fix |
|---|---|---|
| facts | control, attachment, compatibility, or safety detail is unknown | mark recognition pending; obtain a real reference/specification/user confirmation |
| prompt contract | required component/action/effect is absent from compiled context | extend the structured contract and compiler |
| storyboard | action cannot be seen or camera hides the relevant relationship | redesign shot framing and evidence requirements |
| provider/model | model redraws parts, swaps controls, or ignores physical state | add references, reduce motion, switch provider/strategy, keep failed evidence |
| chaining | later segment loses product state or interaction contract | use actual last frame plus original references; block on previous evidence QA |
| QA | wrong output passes because only API status or prompt was checked | require raw video, sampled frames, technical QA, and visual observed fields |
| delivery | raw output has wrong dimensions/audio/codec | normalize and re-check, without overriding visual failures |

After a failure, update the reusable structure template, QA schema, validator, provider adapter, or Skill guidance when the cause is general. A product-specific contract may add facts, but a one-off prompt edit is not a completed fix. Re-run the same scenario after the general fix and report remaining risks.

## Red Flags

Stop and block delivery when any of these occurs:

- The model operates an installation-only part because it resembles a control.
- A detailed prompt is being treated as proof that the action happened.
- Provider task success is being treated as video quality success.
- A normalized crop is being used to hide a raw visual or physical failure.
- A previous segment's terminal frame has not been visually inspected.
- A chained segment inherits an active or ambiguous state when a mutually exclusive state transition is required.
- Product usage is inferred from appearance without a reference, specification, or user confirmation.

Use bundled scripts as starting points:

- `scripts/generate_huya_story_media.py`: Huya image/video generation.
- `scripts/generate_huya_chained_story_videos.py`: actual-last-frame chained generation.
- `scripts/resume_huya_chained_task.py`: recover already-submitted tasks.
- `scripts/render_product_final_template.py`: generic config-driven final-cut renderer. Reads a `render_config.json` (ordered clips, per-clip subtitle cues, title, optional BGM, subtitle style) and outputs a 9:16 hard-concat cut with ASS-burned title + subtitles. No product or market names are hardcoded.

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
