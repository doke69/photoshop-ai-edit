# README 宣传图素材

- hero-v0.4.2.png：使用内置 image_gen 生成。概念示意，不是插件截图或真实生图记录。
- workflow.svg / features.svg：项目内 SVG 矢量排版，文字与图形可直接修改。

## 封面最终生成提示词

Use case: ads-marketing. Asset type: a finished wide landscape hero banner for the README of an open source Photoshop local AI image edit plugin named 局部改图, version v0.4.2. Design a premium restrained dark graphite product editorial banner, around 1800x900 landscape. Large razor-sharp Chinese sans-serif type on the left, subtle blue accent, generous negative space, tasteful professional graphic design, not a cluttered app screenshot. Right side: two beautiful photo-studio product imagery cards depicting the same minimalist ceramic vase with identical silhouette, same beige studio background, one matte cream original and one deep cobalt blue edited vase, a delicate dashed rectangular selection around only the vase in original card, arrow between cards, subtle stacked layer sheets behind the second card. This is a conceptual visual illustration, not a real product screenshot or tested generation output. Exact Chinese text, no extra text: small top eyebrow 'PHOTOSHOP · v0.4.2'; main title '局部改图'; subheadline '圈出要改的地方，把结果带回图层'; three understated feature labels '选区读取' '模型同步' '独立图层'; bottom left short platform line 'macOS / Windows · 支持 OpenUXP 安装'; beneath each vase card labels '原图' and '修改示意'; tiny readable footer '功能概念示意，非实际生成结果'. All text must be accurate, readable, aligned, avoid any invented interface widgets or fabricated numbers, no Adobe logo, no fake software UI, no dramatic 3D chrome, no watermark. Clean typography, precisely aligned two-column grid, fine subtle borders, sophisticated restrained layout.

## 实机界面流程图

- interface-original.png：用户提供的原始截图，未经修改。
- interface-guide.png：使用内置 image_gen 基于该截图辅助排版标注；README 明确标注较早版本及 AI 辅助排版，不用于逐像素核对。

### 生成提示词

Edit target: the attached actual user-provided Photoshop plugin screenshot. Make a clear Chinese annotated usage guide for a GitHub README. Preserve the original screenshot content, every original label, number, image, relative position, frame and color; do not redraw, beautify, change the application UI, invent controls, replace photos, or crop away the bottom result actions. Extend the canvas to the right with a dark graphite annotation column; keep the complete original screenshot on the left at original aspect ratio, with plenty of room for the annotation column. New annotation typography crisp, simple modern Chinese sans-serif. Use six small cobalt blue circular number markers near the relevant screen controls and fine connector lines leading to six aligned instruction blocks in the added right column, without covering important original text. Top of new column title exact '实机界面 · 操作指南'; six annotations exact titles and explanatory lines: '01 选择或新建选区' / '在顶部切换任务；新区域点击「新建」'; '02 读取选区，添加参考' / '先在 PS 框选，再读取；参考图按需添加'; '03 填写修改要求' / '描述想改什么，例如把西装换成红色'; '04 选择模型和参数' / '按模型选择可用清晰度、张数和比例'; '05 点击生成' / '保留当前输入，生成新的候选结果'; '06 预览并添加图层' / '放大、保存或点击添加；支持再次添加'. Relevant targets respectively top region tabs/new at y200, source/reference image area y450, prompt input y720, model options y920, blue generate button y1175, candidate bottom action row y1570. At bottom of right annotation column include exact small honest caption '基于用户实机截图标注，界面为较早版本，当前布局可能略有差异。'. No new claims about results. Readable instructional guide, clean editorial callouts, original screenshot remains primary. Keep all six steps and complete screenshot visible.

### 最终修正提示词

Make precisely one tiny correction to this annotated guide. The small blue circular numbered marker at the right edge of the screenshot next to the model parameters row, approximately x690,y542, currently says 03 but its connector leads to the large 04 annotation. Change ONLY that small marker's text from 03 to 04. Keep every other pixel, layout, text, Chinese typography, screenshot, photos, connector lines, and all other marker numbers unchanged. The prompt-input marker above remains 03. The model-parameters marker must be 04. Do not regenerate the overall design.
