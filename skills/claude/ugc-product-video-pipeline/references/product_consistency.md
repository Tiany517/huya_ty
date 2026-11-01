# Product Consistency Rules

## Structure Recognition

Before prompts, convert product images into a verified structure record:

- Components and visual invariants.
- Relative positions and connection graph.
- Installed/uninstalled/use states.
- Water, power, force, or motion path when applicable.
- Allowed camera motion and forbidden transformations.

A text adjective such as “horizontal” is insufficient. For an attached product, record the exact relation: what attaches to what, which part hangs below, where output exits, and which object remains separate. Keep source images, approved installation anchors, and generated frames in a stable asset manifest.

## Camera Vocabulary

Use one primary effect per shot and encode its Chinese keywords explicitly:

- Push: `推镜头/缓慢推进/急速推进`
- Pull: `拉镜头/逐渐拉远`
- Pan: `左摇/右摇/横移`
- Follow: `跟随镜头/跟拍`
- Orbit: `环绕镜头/360度旋转`
- Crane: `升镜头/降镜头/俯冲`
- Hitchcock zoom: `希区柯克变焦/一镜到底`
- Handheld: `手持晃动`

Every shot also records the subject, amplitude, duration, and start/end framing. Reject conflicting combinations and any motion that hides or changes the product connection topology.


Create `product_constraints.json` before prompts.

Track:

- `observed_from_images`: facts visible in product images.
- `user_claims`: information supplied by the user.
- `assumptions`: inferred but unconfirmed details.
- `must_keep`: constraints repeated in every prompt.
- `must_not_change`: forbidden transformations.

## Visual Constraints

Lock:

- Color.
- Shape.
- Size relative to hand/body/context.
- Material.
- Surface texture.
- Logo or label placement.
- Buttons, nozzles, ports, screens, filters, attachments.
- Installation state.
- Moving parts.
- Package or accessories.

## Prompt Use

Every image and video prompt should include a compact version of product constraints.

Example:

```text
The product must remain palm-sized, silver and white, cylindrical, attached directly to the faucet head. Do not enlarge it, do not change color, do not make it float, do not add screens or buttons.
```

## QA

Inspect frames for:

- Product size drift.
- Shape drift.
- Color drift.
- Extra parts.
- Missing parts.
- Wrong installation.
- Product floating or not interacting with hands/surfaces.
- Physically impossible use.
