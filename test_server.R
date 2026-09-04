# ============================================================
# test_server.R — Shiny testServer 集成测试（验证 server 绑定层）
# 验证：页面浏览 / 搜索 / lint（本次修复点）/ 图谱数据
# 用法: Rscript test_server.R
# ============================================================
library(shiny)
src <- source("app.R", local = TRUE)
app <- src$value

# ---- PDF 集成测试准备：mock llm_answer（避免真实 API 调用，捕获 ctx）----
# 注意：llm_answer 位于 R_GlobalEnv（app 环境链查找终点），Rscript 顶层即 global。
# testServer 的 expr 与 observer 环境链不同，捕获变量必须用 assign 强制写 .GlobalEnv。
orig_llm_answer <- llm_answer
assign("captured_ctx", NULL, envir = .GlobalEnv)
read_captured <- function() tryCatch(
  get("captured_ctx", envir = .GlobalEnv, inherits = FALSE), error = function(e) NULL)
llm_answer <- function(question, context_pages) {
  assign("captured_ctx", list(
    q      = question,
    n      = length(context_pages),
    titles = vapply(context_pages, function(p) p$title, character(1))
  ), envir = .GlobalEnv)
  "MOCK_ANSWER（测试用）"
}
on.exit(llm_answer <- orig_llm_answer, add = TRUE)

# 生成样例 PDF（cupsfilter，macOS 自带；缺失则跳过 PDF 场景）
pdf_path <- NULL
if (file.exists("/usr/sbin/cupsfilter")) {
  pdf_path <- tempfile(fileext = ".pdf")
  src_txt <- tempfile(fileext = ".txt")
  writeLines(c("注意力机制测试文档：", "这是用于验证 PDF 问答模式的样例内容。"), src_txt)
  ok <- system2("/usr/sbin/cupsfilter", src_txt, stdout = pdf_path, stderr = FALSE)
  unlink(src_txt)
  if (ok != 0 || !file.exists(pdf_path)) pdf_path <- NULL
}

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

  # ---- LLM 问答：PDF 上下文组装（llm_answer 已 mock）----
  session$setInputs(qa_question = "请总结测试内容")

  # A. 无 PDF → wiki 全库（原逻辑）
  session$setInputs(qa_go = 1)
  flush()
  cc <- read_captured()
  check("问答[无PDF] ctx=wiki 全库 5 页",
        !is.null(cc) && cc$n == 5,
        if (is.null(cc)) "llm_answer 未触发" else sprintf("n=%d", cc$n))

  if (!is.null(pdf_path)) {
    # B. 上传 PDF + 默认"仅 PDF"模式 → ctx=PDF 虚拟页面
    session$setInputs(pdf_file = list(name = "sample.pdf", size = 1024,
                                      type = "application/pdf", datapath = pdf_path))
    flush()
    pp <- tryCatch(pdf_pages(), error = function(e) NULL)
    check("问答[PDF] pdf_pages 解析成功",
          !is.null(pp) && !is_pdf_error(pp) && length(pp) == 1,
          if (is.null(pp)) "reactive 错误" else sprintf("n=%d", if (is.list(pp)) length(pp) else -1L))
    assign("captured_ctx", NULL, envir = .GlobalEnv)
    session$setInputs(pdf_mode = "pdf_only", qa_go = 2)
    flush()
    cc <- read_captured()
    check("问答[仅PDF] ctx=PDF 1 页（默认模式）",
          !is.null(cc) && cc$n == 1 && startsWith(cc$titles[1], "PDF:"),
          if (is.null(cc)) "llm_answer 未触发"
          else sprintf("n=%d title=%s", cc$n, cc$titles[1]))
    # C. 综合 Wiki + PDF
    assign("captured_ctx", NULL, envir = .GlobalEnv)
    session$setInputs(pdf_mode = "wiki_pdf", qa_go = 3)
    flush()
    cc <- read_captured()
    check("问答[Wiki+PDF] ctx=wiki 5 + PDF 1 = 6 页",
          !is.null(cc) && cc$n == 6,
          if (is.null(cc)) "llm_answer 未触发" else sprintf("n=%d", cc$n))
  } else {
    cat("⚠️ cupsfilter 缺失，跳过 PDF 场景\n")
  }
})

cat(sprintf("\n===== server 集成测试: %d/%d 通过 =====\n", passed, passed + failed))
if (failed > 0) quit(status = 1)
cat("ALL SERVER TESTS PASSED ✅\n")
