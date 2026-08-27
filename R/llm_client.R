# ============================================================
# llm_client.R — DeepSeek API 客户端（问答 / 生成页面 / lint）
# llm_wiki_shiny (GPL v3.0, 衍生自 nashsu/llm_wiki)
# ============================================================

library(httr)
library(jsonlite)

DEEPSEEK_MODEL <- Sys.getenv("LLM_WIKI_MODEL", unset = "deepseek-v4-flash")

# 从 Hermes profile .env 读取 DeepSeek key（绝对路径，避开 HOME 陷阱）
get_deepseek_key <- function() {
  env_file <- "/Users/yuriao/.hermes/profiles/family/.env"
  if (file.exists(env_file)) {
    lines <- readLines(env_file, warn = FALSE)
    hit <- grep("^DEEPSEEK_API_KEY=", lines, value = TRUE)
    if (length(hit) > 0) {
      key <- sub("^DEEPSEEK_API_KEY=", "", hit[1])
      key <- gsub('["\']', "", trimws(key))
      if (nzchar(key)) return(key)
    }
  }
  # 回退到环境变量
  Sys.getenv("DEEPSEEK_API_KEY", unset = "")
}

deepseek_chat <- function(messages, temperature = 0.6, max_tokens = 2000) {
  key <- get_deepseek_key()
  if (!nzchar(key)) stop("未找到 DEEPSEEK_API_KEY，请在 ~/.hermes/profiles/family/.env 配置")
  resp <- POST(
    url = "https://api.deepseek.com/chat/completions",
    add_headers(Authorization = paste("Bearer", key),
                `Content-Type` = "application/json"),
    body = toJSON(list(
      model = DEEPSEEK_MODEL,
      messages = messages,
      temperature = temperature,
      max_tokens = max_tokens
    ), auto_unbox = TRUE),
    timeout(120)
  )
  if (resp$status_code != 200) {
    stop(sprintf("DeepSeek API 错误 %s: %s", resp$status_code,
                 substr(rawToChar(resp$content), 1, 300)))
  }
  parsed <- fromJSON(rawToChar(resp$content), simplifyVector = FALSE)
  msg <- parsed$choices[[1]]$message
  out <- msg$content %||% ""
  # deepseek reasoning 模型：content 可能为空，回退到 reasoning_content
  if (!nzchar(out)) out <- msg$reasoning_content %||% ""
  out
}

# ---- 问答 ----

# 基于 wiki 内容回答（Retrieval 简化为：把相关页面拼进 context）
llm_answer <- function(question, context_pages) {
  ctx <- if (length(context_pages) == 0) "（没有找到相关 wiki 页面）" else
    paste(vapply(context_pages, function(p) {
      sprintf("### 页面：%s（类型：%s）\n%s",
              p$title, p$frontmatter$type %||% "unknown",
              substr(p$body, 1, 2000))
    }, character(1)), collapse = "\n\n")
  messages <- list(
    list(role = "system",
         content = paste0(
           "你是 LLM Wiki 知识库助手。基于以下 wiki 页面内容回答用户问题。",
           "如果页面内容不足以回答，请明确说明。回答用中文，引用相关页面标题。",
           "如果内容与问题无关，只说明无法回答，不要编造。\n\n",
           "=== WIKI 内容 ===\n", ctx)
    ),
    list(role = "user", content = question)
  )
  deepseek_chat(messages)
}

# ---- 生成页面 ----

# 根据主题 + 参考来源生成新 wiki 页面（frontmatter + markdown 正文）
llm_generate_page <- function(title, type, sources) {
  src_txt <- if (length(sources) == 0) "（无，基于通用知识）" else
    paste(sources, collapse = "\n")
  messages <- list(
    list(role = "system", content = paste0(
      "你是知识库编辑。为 wiki 生成一个新页面，输出格式为：\n",
      "第一行：YAML frontmatter（--- 包裹，含 title/type/tags/sources）\n",
      "之后：markdown 正文，包含概述、要点、相关概念（用 [[wikilink]] 语法引用其他页面）。\n",
      "不要输出 frontmatter 之外的解释文字。"
    )),
    list(role = "user", content = sprintf(
      "标题：%s\n类型：%s\n参考来源：\n%s", title, type, src_txt))
  )
  deepseek_chat(messages, temperature = 0.7, max_tokens = 3000)
}

# ---- lint ----

# 检查 wiki 健康状况：孤儿页、断链、缺 frontmatter、过期内容
llm_lint_report <- function(pages_df, wiki_root) {
  if (is.null(pages_df) || nrow(pages_df) == 0) {
    return("wiki 为空，无需检查。")
  }
  titles <- pages_df$title
  title2rel <- stats::setNames(pages_df$relpath, titles)

  issues <- list()
  # 1. 孤儿页（没有被其他页面链接）
  linked_to <- unlist(lapply(seq_len(nrow(pages_df)), function(i) {
    page <- read_wiki_page(pages_df$path[i])
    links <- extract_wikilinks(page$body)
    links[links %in% titles]
  }))
  orphans <- setdiff(titles, linked_to)
  if (length(orphans) > 0)
    issues[[length(issues) + 1]] <- sprintf("孤儿页（无入链）：%s", paste(orphans, collapse = ", "))

  # 2. 断链（链接指向不存在的页面）
  broken <- unique(unlist(lapply(seq_len(nrow(pages_df)), function(i) {
    page <- read_wiki_page(pages_df$path[i])
    links <- extract_wikilinks(page$body)
    links[!links %in% titles]
  })))
  if (length(broken) > 0)
    issues[[length(issues) + 1]] <- sprintf("断链（目标页面不存在）：%s", paste(broken, collapse = ", "))

  # 3. 缺 frontmatter 或必填字段
  no_fm <- vapply(seq_len(nrow(pages_df)), function(i) {
    page <- read_wiki_page(pages_df$path[i])
    is.null(page$frontmatter$title) || is.null(page$frontmatter$type)
  }, logical(1))
  if (any(no_fm))
    issues[[length(issues) + 1]] <- sprintf("缺 frontmatter 必填字段（title/type）：%s",
                                            paste(pages_df$title[no_fm], collapse = ", "))

  # 4. 过期内容（updated 超过 90 天）
  today <- Sys.Date()
  stale <- vapply(seq_len(nrow(pages_df)), function(i) {
    page <- read_wiki_page(pages_df$path[i])
    u <- page$frontmatter$updated %||% ""
    if (!nzchar(as.character(u))) return(FALSE)
    d <- tryCatch(as.Date(as.character(u)), error = function(e) NA)
    !is.na(d) && (today - d) > 90
  }, logical(1))
  if (any(stale))
    issues[[length(issues) + 1]] <- sprintf("内容过期（updated >90 天）：%s",
                                            paste(pages_df$title[stale], collapse = ", "))

  if (length(issues) == 0) return("✅ lint 通过：无孤儿页、无断链、frontmatter 完整、无过期内容。")
  paste(issues, collapse = "\n")
}
