# Cao Cao Actual-Last-Frame Chain Result

## Output

- Final video: `C:\Users\tiany\Desktop\历史人物测试\曹操_图片\final_cut_chain_v2\曹操_成片_实际末帧链式版.mp4`
- Chained clips: `C:\Users\tiany\Desktop\历史人物测试\曹操_图片\videos_chain_v2_huya`
- Actual last frames: `C:\Users\tiany\Desktop\历史人物测试\曹操_图片\chain_v2_frames`

## Result

- Model: `seedance-2.0-fast-cn`
- Segments: 5
- Final duration: 58.537 seconds
- Resolution: 720x1280
- Aspect ratio: 9:16
- `blackdetect`: no black segment detected

## Lessons

1. Actual-last-frame chaining is the right default for final-quality continuity.
2. Video generation must be sequential in chained mode.
3. Recovery from submitted task IDs is necessary to avoid wasting quota.
4. Use one unified BGM in post-production.
5. Keep title/subtitles out of generated frames.
6. Avoid `pad`, `xfade`, `fadeblack`, and black-card transitions.
