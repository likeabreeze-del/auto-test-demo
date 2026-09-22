"""接口用例公共配置：统一 BASE_URL、导入请求封装与失败日志。"""
import json
import os
import time
from pathlib import Path

import requests

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8765")
IMPORT_URL = f"{BASE_URL}/api/assets/import"

PROJECT_ROOT = Path(__file__).resolve().parents[2]
LOG_FILE = PROJECT_ROOT / "logs" / "api_failures.log"


def do_import(payload: dict, testcase: str) -> requests.Response:
    """调用导入接口；当返回非 200 时把请求体、状态码、响应体写入失败日志。"""
    resp = requests.post(IMPORT_URL, json=payload, timeout=10)
    if resp.status_code != 200:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"=== {time.strftime('%Y-%m-%d %H:%M:%S')} [{testcase}] ===\n")
            f.write(f"URL: {IMPORT_URL}\n")
            f.write(f"请求体: {json.dumps(payload, ensure_ascii=False)}\n")
            f.write(f"响应状态码: {resp.status_code}\n")
            f.write(f"响应体: {resp.text}\n\n")
    return resp
