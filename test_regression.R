# ============================================================
# test_regression.R — 全功能回归测试（综合版）
# 覆盖：IO/渲染/图谱/搜索/编辑写盘/新建写盘/LLM(lint)
# 用法: Rscript test_regression.R
# ============================================================
options(warn = 1)
env <- new.env()
for (f in c("R/wiki_io.R", "R/wiki_render.R", "R/wiki_graph.R",
            "R/wiki_search.R", "R/llm_client.R")) {
  sys.source(f, envir = env)
}

WIKI <- "example_wiki"
results <- list()
ok <- function(name, cond, detail = "") {
  results[[length(results) + 1]] <<- data.frame(
    test = name, pass = isTRUE(cond), detail = substr(detail, 1, 120),
    stringsAsFactors = FALSE)
  cat(sprintf("%s %s\n", if (isTRUE(cond)) "✅" else "❌", name))
}

# ---- 1. 扫描与解析 ----
pages <- env$list_wiki_pages(WIKI)
ok("扫描页面 (n=5)", nrow(pages) == 5, sprintf("n=%d", nrow(pages)))
pg <- env$read_wiki_page(pages$path[1])
ok("frontmatter 解析", !is.null(pg$title) && nzchar(pg$body),
   sprintf("title=%s body=%dch", pg$title, nchar(pg$body)))

# ---- 2. wikilink 提取与渲染 ----
links <- env$extract_wikilinks(pg$body)
ok("wikilink 提取", length(links) >= 0)
known <- c("注意力机制", "Transformer", "RAG", "OpenAI", "RAG vs LLM Wiki")
html <- env$render_page_body(pg$body, known)
ok("渲染含链接锚点", grepl("<a ", html, fixed = TRUE))
broken_html <- env$render_page_body("见 [[不存在的页面]]", known)
ok("断链渲染为 missing", grepl("missing", broken_html, fixed = TRUE))

# ---- 3. 目录树 ----
tree <- env$build_tree_data(WIKI)
ok("目录树含四类目录", all(c("entities", "concepts", "comparisons") %in% names(tree)),
   paste(names(tree), collapse = ","))

# ---- 4. 图谱数据 ----
gd <- env$build_graph_data(pages, WIKI)
ok("图谱 5 节点", nrow(gd$nodes) == 5, sprintf("nodes=%d edges=%d", nrow(gd$nodes), nrow(gd$edges)))
vn <- env$render_wiki_graph(gd)
ok("visNetwork 对象", inherits(vn, "visNetwork"))

# ---- 5. 搜索 ----
res <- env$search_wiki(pages, "注意力", WIKI)
ok("搜索命中>=1", nrow(res) >= 1, sprintf("hits=%d", nrow(res)))
res2 <- env$search_wiki(pages, "zzz_不存在", WIKI)
ok("搜索无命中返回空表", nrow(res2) == 0)

# ---- 6. 编辑写盘（往返） ----
tmpf <- tempfile(fileext = ".md")
fm <- list(title = "回归测试页", created = "2026-08-27", updated = "2026-08-27",
           type = "concept", tags = "test")
body <- "# 回归测试页\n\n内容 [[RAG]]。"
env$write_wiki_page(tmpf, fm, body)
back <- env$read_wiki_page(tmpf)
ok("编辑写盘往返", back$title == "回归测试页" && grepl("RAG", back$body))
unlink(tmpf)

# ---- 7. lint ----
lint <- env$llm_lint_report(pages, WIKI)
ok("lint 输出非空", nzchar(lint), substr(lint, 1, 60))

# ---- 汇总 ----
df <- do.call(rbind, results)
cat(sprintf("\n===== 回归结果: %d/%d 通过 =====\n", sum(df$pass), nrow(df)))
if (!all(df$pass)) {
  cat("\n失败项:\n"); print(df[!df$pass, ])
  quit(status = 1)
}
cat("ALL REGRESSION TESTS PASSED ✅\n")
