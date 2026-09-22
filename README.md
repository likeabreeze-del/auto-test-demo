# 中台资产管理平台 · 自动化测试 Demo 工程

自包含的自动化测试演示工程（用于飞书项目 AI 节点调用演示），**不依赖任何外部线上环境**：mock 服务、被测页面、用例与报告全部在本工程内闭环。

## 工程结构

```
├── mock_server/          # FastAPI 极简 mock 服务（模拟“中台资产管理平台”）
│   ├── app.py            #   /api/assets/import 导入接口 + /api/health、/api/assets
│   └── static/           #   Web UI 演示页：首页 / 资产列表 / 资产导入
├── tests/
│   ├── api/              # 接口用例（pytest + requests，32 条）
│   └── web/              # Web UI 用例（Playwright，16 条）
├── scripts/gen_report.py # 汇总 junit xml 生成报告
├── run.sh                # 一键运行入口（mock 服务 + 接口用例 + 报告）
├── results/              # 运行后生成：report.json / report.md
├── logs/                 # 接口失败日志：api_failures.log
└── screenshots/          # Web 用例失败截图
```

## 已知缺陷（演示用）

`POST /api/assets/import`：当资产名包含 `<`、`>`、`&`、英文双引号等特殊字符时，服务端未做转义，返回 **HTTP 500**。对应已知缺陷用例 `test_032_import_name_with_special_chars`（预期失败，实际返回 500）。

## 用例设计

| 分组 | 工具 | 总数 | 通过 | 失败 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 接口用例 | pytest + requests | 32 | 31 | 1 | 唯一失败为“特殊字符资产名导入”（已知缺陷） |
| Web UI 用例 | Playwright (Python, Chromium) | 16 | 16 | 0 | 覆盖 3 个静态演示页 |

- 接口用例失败时：请求体、响应状态码、响应体写入 `logs/api_failures.log`
- Web 用例失败时：自动整页截图到 `screenshots/<用例名>.png`
- `run.sh` 默认只执行接口用例（沙箱可能没有浏览器，避免整体失败）；Web UI 用例文件保留，可手动触发（见下文）

## 安装依赖

要求 Python ≥ 3.9。

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

> 执行接口用例（`run.sh` 默认行为）无需任何浏览器。
> 若要运行 Web UI 用例，额外安装 Playwright：
>
> ```bash
> .venv/bin/pip install playwright
> .venv/bin/playwright install chromium   # 下载失败且本机装有 Google Chrome 时会自动降级用本机 Chrome
> ```

## 运行

```bash
bash run.sh        # 或先 chmod +x run.sh && ./run.sh
```

流程：启动 mock 服务（127.0.0.1:8765）→ 跑接口用例 → 生成报告。Web UI 用例不在默认执行序列内，需要时手动运行：

```bash
BASE_URL=http://127.0.0.1:8765 .venv/bin/python -m pytest tests/web
```

结束后查看：

- `results/report.json` / `results/report.md`：两组用例总数、通过数、失败数、通过率、失败明细及证据文件路径
- `logs/api_failures.log`：失败接口用例的请求/响应证据
- `screenshots/`：失败 Web 用例截图

`run.sh` 预期结果：**接口用例 31 通过 / 1 失败（通过率 96.88%）**，唯一失败为已知缺陷用例，报告中 Web UI 用例标注「未执行」；补跑 Web UI 用例后总计 **47 通过 / 1 失败（通过率 97.92%）**。

## 环境变量（可选）

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | 8765 | mock 服务端口 |
| `BASE_URL` | `http://127.0.0.1:8765` | 用例访问的服务地址（run.sh 会自动传入） |
| `PYTHON` | `python3` | 指定解释器（工程内存在 `.venv` 时优先使用） |
