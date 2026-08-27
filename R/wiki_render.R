# ============================================================
# wiki_render.R — Markdown 渲染 + [[wikilinks]] 转换 + frontmatter 展示
# llm_wiki_shiny (GPL v3.0, 衍生自 nashsu/llm_wiki)
# ============================================================

# 把 [[目标]] / [[目标|显示名]] 转换为应用内导航链接
# 点击通过 Shiny.setInputValue('wikilink_click', 目标标题) 切换页面（不刷新，保留状态）
transform_wikilinks <- function(text, known_titles) {
  if (is.null(text) || !nzchar(text)) return(text)
  m <- gregexpr("\\[\\[[^\\[\\]\\n]+?\\]\\]", text, perl = TRUE)[[1]]
  if (m[1] == -1) return(text)
  hits <- regmatches(text, list(m))[[1]]
  replacements <- vapply(hits, function(match) {
    inner <- substr(match, 3, nchar(match) - 2)
    parts <- strsplit(inner, "|", fixed = TRUE)[[1]]
    target <- trimws(parts[1])
    label  <- if (length(parts) > 1) trimws(parts[2]) else target
    js_target <- gsub("'", "\\\\'", target)
    if (target %in% known_titles) {
      sprintf('<a class="wikilink" href="#" onclick="Shiny.setInputValue(\'wikilink_click\', \'%s\', {priority:\'event\'}); return false;">%s</a>',
              js_target, label)
    } else {
      sprintf('<span class="wikilink-missing" title="页面不存在">%s</span>', label)
    }
  }, character(1))
  out <- text
  regmatches(out, list(m)) <- list(replacements)
  out
}

# 渲染 markdown 正文 → HTML（已处理 wikilink）
render_page_body <- function(body, known_titles) {
  if (is.null(body) || !nzchar(body)) return("")
  html_body <- transform_wikilinks(body, known_titles = known_titles)
  commonmark::markdown_html(html_body, hardbreaks = FALSE)
}

# frontmatter → 展示卡片（表格）
frontmatter_to_html <- function(fm) {
  if (length(fm) == 0) return("")
  rows <- vapply(names(fm), function(k) {
    v <- fm[[k]]
    if (is.list(v) || length(v) > 1) v <- paste(unlist(v), collapse = ", ")
    sprintf("<tr><th>%s</th><td>%s</td></tr>",
            htmltools::htmlEscape(k),
            htmltools::htmlEscape(as.character(v)))
  }, character(1))
  paste0('<table class="frontmatter-table">', paste(rows, collapse = ""), "</table>")
}

# 完整页面 HTML（frontmatter 卡片 + 正文）
render_wiki_page <- function(page, known_titles) {
  fm_html <- frontmatter_to_html(page$frontmatter)
  body_html <- render_page_body(page$body, known_titles)
  paste0(fm_html, body_html)
}
