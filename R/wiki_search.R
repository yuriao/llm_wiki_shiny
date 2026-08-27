# ============================================================
# wiki_search.R — 全文搜索（标题 + frontmatter + 正文）
# llm_wiki_shiny (GPL v3.0, 衍生自 nashsu/llm_wiki)
# ============================================================

# 在页面集合中搜索关键词，返回 data.frame（文件、标题、类型、匹配片段）
search_wiki <- function(pages_df, query, wiki_root) {
  if (is.null(pages_df) || nrow(pages_df) == 0 || !nzchar(trimws(query))) {
    return(data.frame())
  }
  q <- tolower(trimws(query))
  results <- lapply(seq_len(nrow(pages_df)), function(i) {
    page <- read_wiki_page(pages_df$path[i])
    title_hit <- grepl(q, tolower(page$title), fixed = TRUE)
    fm_hit    <- grepl(q, tolower(paste(unlist(page$frontmatter), collapse = " ")), fixed = TRUE)
    body_hit  <- grepl(q, tolower(page$body), fixed = TRUE)
    if (!(title_hit || fm_hit || body_hit)) return(NULL)
    # 提取匹配片段（正文中第一次出现位置 ± 60 字符）
    snippet <- ""
    if (body_hit) {
      pos <- regexpr(q, tolower(page$body), fixed = TRUE)[1]
      if (pos > 0) {
        start <- max(1, pos - 60)
        end   <- min(nchar(page$body), pos + 80)
        snippet <- paste0("…", substr(page$body, start, end), "…")
      }
    }
    data.frame(
      path    = pages_df$path[i],
      relpath = pages_df$relpath[i],
      title   = page$title,
      type    = pages_df$type[i],
      hit_in  = paste(c(if (title_hit) "标题", if (fm_hit) "frontmatter",
                        if (body_hit) "正文"), collapse = ", "),
      snippet = snippet,
      stringsAsFactors = FALSE
    )
  })
  res <- Filter(Negate(is.null), results)
  if (length(res) == 0) return(data.frame())
  do.call(rbind, res)
}
