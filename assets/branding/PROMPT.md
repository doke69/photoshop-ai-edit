# Photoshop AI Edit 图标

生成工具：内置 imagegen。日期：2026-10-18。

当前应用源图：`app-icon.png`，为 v3 真透明圆角母版。下方 v1 / v2 仅保留历史记录，不再作为生产生成要求。设计主题：选区框 + 局部焕新；独立插件品牌，不使用 Adobe 标识。

原始提示词：

> Use case: logo-brand. Create a single polished original macOS app icon for Photoshop AI Edit, an independent AI local image editing plugin. Square 1024x1024 composition. Deep midnight navy rounded-square tile with generous inset safe margin. Center a bold simple white/cyan selection-frame motif made of four rounded L-shaped corners, with one small vivid electric blue-to-mint four-point editing sparkle at the upper-right of the inner selection. A subtle overlapping luminous cyan image plane suggests editing only part of an image. Excellent silhouette and legibility at 32 pixels, restrained premium desktop creative-tool design, balanced geometry, very subtle dimensional soft lighting, mostly flat, no excessive glow. Fill square canvas with dark navy surrounding the rounded tile; no lettering, no text, no Adobe logo, no Ps initials, no mockup, no multiple variants, no watermark.

## v2：铺满母版与原生图标输出（已废止）

工具：内置 imagegen，以原图为编辑参考。原始输出保留为 `app-icon-v2.png`；`app-icon.png` 为 1024 × 1024 输出母版。移除嵌套小圆角底板，背景铺满画布，放大选区与焕新符号。当时错误地假设本项目的程序坞图标会由系统自动处理外轮廓，结果实际 ICNS / Dock 仍显示深色矩形；该生产方案已废止。

编辑提示词：

> Edit this app icon, preserving its recognizable selection-corner frame, blue image plane and cyan sparkle. Deliver a single square full-bleed macOS app-icon master artwork, 1024x1024. Enlarge and recompose the symbol to occupy the icon confidently: the selection frame should extend from roughly 12% to 88% of canvas width, the image plane from 10% to 75%, the sparkle at upper-right fully inside safe area. Remove the small inset rounded-square tile and all external padding, outer vignette, drop shadow and outer framing. The deep midnight-blue background must run flush to all four edges of the square canvas, with NO baked-in outer rounded corners, NO smaller tile sitting within another background. The system or production packaging will apply the macOS icon shape. Strong small-size legibility, cleaner broader corner strokes, crisp soft-lit blue/cyan/white materials, visually centered. No text, letters, Adobe logos, mockups or surrounding UI. This is the updated master logo, not an installer-package illustration.


## v3：透明圆角抠图（当前）

工具：内置 imagegen，使用用户选定原图 `windows-installer.png` 作为编辑输入。生成输出原样保存为 `app-icon.png`（1254 × 1254 RGBA），保留其透明通道；Mac 与 Windows 共用此母版。白／深色／棋盘背景与系统图标检查见 [检查记录](ICON-QA-v047.md)。

最终编辑提示词：

> Use case: background-extraction. Edit the attached image, do not redesign it. Deliver a production app icon as a real transparent-background PNG. The subject to KEEP is the entire glossy deep-blue rounded-square app icon body (its curved boundary is clearly visible starting near x110,y110 in the 1254px reference), including all of the internal white crop-corner brackets, overlapping cyan/blue landscape pictures and glowing cyan star. REMOVE only the dark navy square background OUTSIDE the rounded-square body. Follow the actual smooth curved silhouette, not a rectangular crop and not an arbitrary circular mask. Keep the blue rounded body fully opaque, with smooth antialiased alpha only at its outer edge. Completely transparent outside: every canvas corner and the surrounding exterior must be alpha=0, with NO opaque navy mat, NO checkerboard drawn into pixels, NO extra backdrop, NO added shadow around the outside, NO border. Preserve the original design, proportions, material, highlights, colors and arrangement as closely as possible. Keep the original centered composition and approximately 8-9% transparent margin around the outermost blue rounded-square body, appropriate for a macOS Dock/Windows ICO. One single isolated rounded-square icon on a square transparent canvas. No text.
