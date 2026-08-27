# Wiki Schema

## Domain
AI/ML 研究知识库（LLM Wiki 模式演示）

## Conventions
- 文件命名：小写、连字符（如 `transformer-architecture.md`）
- 每页含 YAML frontmatter（title/created/updated/type/tags）
- 用 `[[wikilinks]]` 交叉引用（每页至少 2 个出链）
- 新页面必须登记到 index.md；每次操作记入 log.md

## Three Layers
- **Layer 1 raw/**：不可变原始材料
- **Layer 2 entities|concepts|comparisons|queries**：wiki 页面
- **Layer 3 SCHEMA.md**：规则与配置

## Tag Taxonomy
- model, architecture, technique, company, comparison
