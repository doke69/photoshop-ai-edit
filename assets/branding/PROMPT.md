# Photoshop AI Edit 图标

生成工具：内置 imagegen。日期：2026-10-18。

应用源图：`app-icon.png`。设计主题：选区框 + 局部焕新；独立插件品牌，不使用 Adobe 标识。

原始提示词：

> Use case: logo-brand. Create a single polished original macOS app icon for Photoshop AI Edit, an independent AI local image editing plugin. Square 1024x1024 composition. Deep midnight navy rounded-square tile with generous inset safe margin. Center a bold simple white/cyan selection-frame motif made of four rounded L-shaped corners, with one small vivid electric blue-to-mint four-point editing sparkle at the upper-right of the inner selection. A subtle overlapping luminous cyan image plane suggests editing only part of an image. Excellent silhouette and legibility at 32 pixels, restrained premium desktop creative-tool design, balanced geometry, very subtle dimensional soft lighting, mostly flat, no excessive glow. Fill square canvas with dark navy surrounding the rounded tile; no lettering, no text, no Adobe logo, no Ps initials, no mockup, no multiple variants, no watermark.

## v2：铺满母版与原生图标输出

工具：内置 imagegen，以原图为编辑参考。原始输出保留为 `app-icon-v2.png`；`app-icon.png` 为 1024 × 1024 输出母版。移除嵌套小圆角底板，背景铺满画布，放大选区与焕新符号。按 Apple 当前指南提供未预遮罩的正方形母版，并使用 macOS 原生 iconutil 生成多尺寸 ICNS。

编辑提示词：

> Edit this app icon, preserving its recognizable selection-corner frame, blue image plane and cyan sparkle. Deliver a single square full-bleed macOS app-icon master artwork, 1024x1024. Enlarge and recompose the symbol to occupy the icon confidently: the selection frame should extend from roughly 12% to 88% of canvas width, the image plane from 10% to 75%, the sparkle at upper-right fully inside safe area. Remove the small inset rounded-square tile and all external padding, outer vignette, drop shadow and outer framing. The deep midnight-blue background must run flush to all four edges of the square canvas, with NO baked-in outer rounded corners, NO smaller tile sitting within another background. The system or production packaging will apply the macOS icon shape. Strong small-size legibility, cleaner broader corner strokes, crisp soft-lit blue/cyan/white materials, visually centered. No text, letters, Adobe logos, mockups or surrounding UI. This is the updated master logo, not an installer-package illustration.
