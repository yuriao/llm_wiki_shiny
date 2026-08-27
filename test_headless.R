# headless 逻辑测试 — 验证各模块函数
root <- normalizePath("example_wiki")
for (f in c("wiki_io.R", "wiki_render.R", "wiki_graph.R", "wiki_search.R", "llm_client.R"))
  sys.source(file.path("R", f), envir = globalenv())

cat("=== 1. list_wiki_pages ===\n")
pages <- list_wiki_pages(root)
print(pages[, c("title", "type", "relpath")])
stopifnot(nrow(pages) == 5)

cat("\n=== 2. parse_frontmatter / read_wiki_page ===\n")
p <- read_wiki_page(pages$path[1])
stopifnot(!is.null(p$frontmatter$title), nzchar(p$body))
cat("title:", p$title, "| type:", p$frontmatter$type, "| body nchar:", nchar(p$body), "\n")

cat("\n=== 3. build_tree_data ===\n")
tree <- build_tree_data(root)
cat("top-level keys:", paste(names(tree), collapse = ", "), "\n")
stopifnot(all(c("entities", "concepts", "SCHEMA.md", "index.md") %in% names(tree)))

cat("\n=== 4. extract_wikilinks ===\n")
links <- extract_wikilinks(p$body)
cat("transformer links:", paste(links, collapse = ", "), "\n")
stopifnot(length(links) >= 2)

cat("\n=== 5. transform_wikilinks / render_page_body ===\n")
titles <- pages$title
html <- render_page_body(p$body, titles)
cat("contains wikilink anchor:", grepl("wikilink", html, fixed = TRUE), "\n")
cat("contains missing-span:", grepl("wikilink-missing", html, fixed = TRUE), "\n")
stopifnot(grepl("class=\"wikilink\"", html, fixed = TRUE))

cat("\n=== 6. build_graph_data ===\n")
g <- build_graph_data(pages, root)
cat("nodes:", nrow(g$nodes), "| edges:", nrow(g$edges), "\n")
print(g$edges)
stopifnot(nrow(g$nodes) == 5, nrow(g$edges) >= 6)

cat("\n=== 7. search_wiki ===\n")
res <- search_wiki(pages, "注意力", root)
print(res[, c("title", "hit_in")])
stopifnot(nrow(res) >= 2)

cat("\n=== 8. render_wiki_graph (visNetwork object) ===\n")
vn <- render_wiki_graph(g)
cat("class:", class(vn)[1], "\n")
stopifnot(inherits(vn, "visNetwork"))

cat("\n=== 9. llm_lint_report ===\n")
lint <- llm_lint_report(pages, root)
cat(lint, "\n")
stopifnot(grepl("断链", lint))  # 应报 attention 里的 [[知识图谱]] 断链

cat("\n=== ALL HEADLESS TESTS PASSED ✅ ===\n")
