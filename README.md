# LLM Wiki Shiny

基于 [nashsu/llm_wiki](https://github.com/nashsu/llm_wiki) 思想移植的 **R Shiny 知识库应用**：本地 Markdown 双层结构 wiki + 知识图谱 + 全文搜索 + DeepSeek LLM 增强。

## ✨ 功能

| 模块 | 说明 |
|------|------|
| 📖 浏览 | 左侧三层目录树，点击打开页面；frontmatter 元数据卡片 + wikilink 双向链接渲染 |
| 🕸️ 知识图谱 | visNetwork 力导向图，节点按类型着色，点击节点跳转页面 |
| 🔍 搜索 | 全文搜索（标题 + frontmatter + 正文），返回匹配片段 |
| ✏️ 编辑/新建 | 模态框编辑页面（YAML frontmatter + Markdown 正文），自动落盘 |
| 🤖 LLM | DeepSeek 驱动：基于 wiki 上下文问答 / 一键生成新页面 / wiki 健康 lint（孤儿页、断链、过期内容） |

## 🏗️ 目录结构

```
llm_wiki_shiny/
├── app.R                  # UI + server（bslib 三栏布局）
├── R/
│   ├── wiki_io.R          # 文件 IO、frontmatter 解析、目录树、[[links]] 提取
│   ├── wiki_render.R      # Markdown 渲染 + wikilink 转换 + frontmatter 卡片
│   ├── wiki_graph.R       # 知识图谱（visNetwork）
│   ├── wiki_search.R      # 全文搜索
│   └── llm_client.R       # DeepSeek 客户端（问答/生成/lint）
├── example_wiki/          # 示例 wiki（中文，5 页）
│   ├── SCHEMA.md / index.md / log.md
│   ├── entities/ concepts/ comparisons/
│   └── raw/articles/      # 原始参考笔记
└── test_headless.R        # headless 逻辑测试
```

## Wiki 页面格式

每个页面是一个 Markdown 文件，YAML frontmatter 在前，正文在后：

```markdown
---
title: Transformer
created: 2026-08-24
updated: 2026-08-24
type: entity        # entity / concept / comparison
tags: [model, architecture]
sources: [raw/articles/karpathy-gist.md]
---

# Transformer

Transformer 是 2017 年提出的……完全基于 [[注意力机制]]……
```

- `[[wikilink]]` 引用其他页面标题，自动转为可点击链接，断链显示为灰色样式
- 页面按 `type` 放在 `entities/`、`concepts/`、`comparisons/` 子目录

## 🚀 运行

### 依赖

```r
install.packages(c("shiny", "bslib", "shinyTree", "visNetwork", "DT",
                   "markdown", "yaml", "httr", "jsonlite"))
```

### 启动

```bash
Rscript -e 'src <- source("app.R", local=TRUE);
            runApp(src$value, port=8100, host="127.0.0.1", launch.browser=FALSE)'
```

打开 http://127.0.0.1:8100/ 即可。左侧可切换任意 wiki 根目录。

### LLM 配置

LLM 功能需要 DeepSeek API key，两种方式（二选一）：

1. 环境变量：`export DEEPSEEK_API_KEY=sk-...`
2. 配置文件：`~/.hermes/profiles/family/.env` 中的 `DEEPSEEK_API_KEY=sk-...`

默认模型 `deepseek-v4-flash`，可用环境变量 `LLM_WIKI_MODEL` 覆盖。

## 🧪 测试

```bash
Rscript test_headless.R   # 扫描/解析/树/链接/图谱/搜索/lint 逻辑测试
```

## ⚖️ License

GPL v3.0 — 本项目衍生自 [nashsu/llm_wiki](https://github.com/nashsu/llm_wiki)（GPL-3.0）。完整协议见 [LICENSE](LICENSE)。

> 摘要：你可以自由使用、修改、分发本软件，但**修改后的衍生作品必须以相同许可证（GPL-3.0）开源**，并保留版权声明。
