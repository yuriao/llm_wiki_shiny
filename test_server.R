# ============================================================
# test_server.R — Shiny testServer 集成测试（验证 server 绑定层）
# 验证：页面浏览 / 搜索 / lint（本次修复点）/ 图谱数据
# 用法: Rscript test_server.R
# ============================================================
library(shiny)
src <- source("app.R", local = TRUE)
app <- src$value

passed <- 0; failed <- 0
check <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { passed <<- passed + 1; cat(sprintf("✅ %s\n", name)) }
  else { failed <<- failed + 1; cat(sprintf("❌ %s — %s\n", name, detail)) }
}

testServer(app, {
  flush <- function() { session$flushReact(); Sys.sleep(0.3) }

  # ---- 初始状态：页面数 ----
  flush()
  stats <- output$wiki_stats
  check("wiki_stats 输出", grepl("页面数：5", stats), stats)

  # ---- 浏览：选择页面 ----
  pages <- pages_df()
  check("pages_df 5 页", nrow(pages) == 5, sprintf("n=%d", nrow(pages)))
  session$setInputs(tree_click = paste0("page::", pages$path[1]))
  flush()
  check("树点击设置当前页面", identical(rv$current_rel, pages$relpath[1]),
        sprintf("rel=%s", rv$current_rel))
  pg <- tryCatch(current_page(), error = function(e) structure(list(err = conditionMessage(e)), class = "err"))
  check("当前页面可读取", !is.null(pg) && !inherits(pg, "err") && nzchar(pg$title),
        if (inherits(pg, "err")) paste("ERR:", pg$err) else if (is.null(pg)) "NULL" else pg$title)

  # ---- 搜索 ----
  session$setInputs(search_q = "RAG", search_go = 1)
  flush()
  check("搜索结果非空", nrow(search_res()) > 0, sprintf("n=%d", nrow(search_res())))

  # ---- lint（本次修复点）----
  session$setInputs(lint_go = 1)
  flush()
  lint_txt <- paste(output$lint_result, collapse = " ")
  check("lint 输出非空", nzchar(trimws(lint_txt)), lint_txt)
  check("lint 检出断链", grepl("断链", lint_txt), lint_txt)

  # ---- 图谱 ----
  gd <- build_graph_data(pages_df(), rv$wiki_root)
  check("图谱 5 节点 11 边", nrow(gd$nodes) == 5 && nrow(gd$edges) == 11,
        sprintf("n=%d e=%d", nrow(gd$nodes), nrow(gd$edges)))
})

cat(sprintf("\n===== server 集成测试: %d/%d 通过 =====\n", passed, passed + failed))
if (failed > 0) quit(status = 1)
cat("ALL SERVER TESTS PASSED ✅\n")
