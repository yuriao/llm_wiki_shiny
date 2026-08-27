---
source_url: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
ingested: 2026-08-24
---

# Karpathy's LLM Wiki 原始笔记（摘录）

LLM wiki 是一种知识积累模式：让 LLM 把摄入的材料编译成互链的 markdown 页面。

- 三层：raw（原始）→ wiki（编译）→ schema（规则）
- 三操作：ingest / query / lint
- index.md 是导航入口；log.md 是操作记录
- [[wikilinks]] 建立交叉引用；frontmatter 提供元数据
