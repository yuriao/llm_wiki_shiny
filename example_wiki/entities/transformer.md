---
title: Transformer
created: 2026-08-24
updated: 2026-08-24
type: entity
tags: [model, architecture]
sources: [raw/articles/karpathy-gist.md]
---

# Transformer

Transformer 是 2017 年提出的深度学习架构，完全基于 [[注意力机制]]，摒弃了循环结构。

## 核心要点

- **自注意力**：输入序列中每个位置与所有其他位置交互，并行计算
- **位置编码**：为并行处理补充顺序信息
- **规模效应**：参数量增大时能力持续提升（scaling law）

## 影响

- 现代大语言模型（GPT、Claude 等）的基础
- [[OpenAI]] 的 GPT 系列基于此架构
- 取代了 RNN/LSTM 成为序列建模主流

## 相关
- [[注意力机制]]
- [[RAG]]
