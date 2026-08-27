---
title: 注意力机制
created: 2026-08-24
updated: 2026-08-24
type: concept
tags: [technique, architecture]
sources: []
---

# 注意力机制

注意力机制允许模型在处理序列时动态聚焦于最相关的部分。

## 定义

- Query、Key、Value 三组向量
- 通过 Q·K 相似度加权 V
- 多头注意力并行捕捉不同子空间关系

## 地位

- [[Transformer]] 的核心组件
- 也是现代 LLM 理解长文本的关键
- 与 [[知识图谱]] 不同：注意力是隐式的，图谱是显式的

## 相关
- [[Transformer]]
- [[RAG]]
