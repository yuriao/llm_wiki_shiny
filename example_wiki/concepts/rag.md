---
title: RAG
created: 2026-08-24
updated: 2026-08-24
type: concept
tags: [technique]
sources: []
---

# RAG（检索增强生成）

RAG 是让 LLM 在回答前先从外部知识库检索相关片段的范式。

## 工作方式

1. 文档切块 → 向量化 → 存入向量数据库
2. 用户提问时检索 Top-K 相关块
3. 把检索结果拼进 prompt，让 LLM 基于上下文回答

## 与 LLM Wiki 的对比

- RAG：每次查询都重新检索，知识不被编译
- LLM Wiki：知识被**预先编译**成交互链接的页面（见 [[RAG vs LLM Wiki]]）
- RAG 适合大规模非结构化语料；Wiki 适合长期积累的领域知识

## 相关
- [[RAG vs LLM Wiki]]
- [[Transformer]]
