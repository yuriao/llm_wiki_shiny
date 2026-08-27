---
title: RAG vs LLM Wiki
created: 2026-08-24
updated: 2026-08-24
type: comparison
tags: [comparison, technique]
sources: [raw/articles/karpathy-gist.md]
---

# RAG vs LLM Wiki

两种让 LLM 利用外部知识的方式对比。

## 对比表

| 维度 | RAG | LLM Wiki |
|------|-----|----------|
| 知识形态 | 向量块（无结构） | 互链 Markdown 页面 |
| 查询代价 | 每次重新检索 | 直接读编译结果 |
| 积累效应 | 无（每次从头） | 有（持续编译） |
| 交叉引用 | 无 | [[wikilinks]] |
| 矛盾处理 | 不感知 | 显式标注 |

## 结论

- 高频、结构化、需长期积累的领域 → LLM Wiki 更优
- 海量、开放、非结构化语料 → RAG 更合适
- 两者可互补：Wiki 作为精编层，RAG 作为泛检索层

## 相关
- [[RAG]]
- [[Transformer]]
