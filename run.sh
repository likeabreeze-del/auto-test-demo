#!/usr/bin/env bash
# 一键运行：启动 mock 服务 -> 跑接口用例 -> 生成测试报告
# Web UI 用例（tests/web/）默认不在执行序列内（沙箱可能无浏览器），
# 文件保留，需要时可手动运行：pytest tests/web（另需安装 playwright，见 README）。
set -u
cd "$(dirname "$0")"

# Python 解释器：优先用工程内 venv
PY="${PYTHON:-python3}"
if [ -x ".venv/bin/python" ]; then PY=".venv/bin/python"; fi

PORT="${PORT:-8765}"
BASE_URL="http://127.0.0.1:${PORT}"

mkdir -p logs results
rm -f logs/api_failures.log
rm -f results/api_junit.xml results/web_junit.xml results/report.json results/report.md

echo "==> [1/3] 启动 mock 服务 (中台资产管理平台): ${BASE_URL}"
"$PY" -m uvicorn mock_server.app:app --host 127.0.0.1 --port "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null' EXIT

for i in $(seq 1 60); do
  if curl -sf "${BASE_URL}/api/health" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then echo "mock 服务启动失败"; exit 1; fi
  sleep 0.5
done

echo "==> [2/3] 运行接口用例 (pytest + requests)"
BASE_URL="$BASE_URL" "$PY" -m pytest tests/api --junitxml=results/api_junit.xml -q
API_RC=$?

echo "==> [3/3] 生成测试报告"
"$PY" scripts/gen_report.py
REPORT_RC=$?

kill "$SERVER_PID" 2>/dev/null
trap - EXIT

echo
echo "接口用例退出码: ${API_RC} | 报告退出码: ${REPORT_RC}"
echo "报告文件: results/report.json / results/report.md"
echo "完成。（接口用例按设计 31 过 1 败：特殊字符资产名导入为已知缺陷用例；Web UI 用例未执行）"
