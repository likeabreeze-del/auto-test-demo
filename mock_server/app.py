"""中台资产管理平台 —— Mock 服务（演示用，不依赖任何外部线上环境）。

已知缺陷（用于演示）：资产名包含 < > & " 等特殊字符时，
导入服务未做转义，直接返回 HTTP 500。
"""
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

STATIC_DIR = Path(__file__).parent / "static"

app = FastAPI(title="中台资产管理平台 Mock", version="1.0.0")

SPECIAL_CHARS = ("<", ">", "&", '"')

# 内存态资产数据（仅演示）
ASSETS = [
    {"id": "AST-1001", "name": "核心交换机-SW-01", "type": "网络设备", "status": "运行中"},
    {"id": "AST-1002", "name": "办公笔记本-LT-1024", "type": "终端设备", "status": "运行中"},
    {"id": "AST-1003", "name": "数据库服务器-DB-03", "type": "服务器", "status": "维护中"},
    {"id": "AST-1004", "name": "打印机-PR-08", "type": "办公设备", "status": "已停用"},
    {"id": "AST-1005", "name": "防火墙-FW-02", "type": "网络设备", "status": "运行中"},
]


@app.get("/api/health")
def health():
    return {"status": "ok", "service": "asset-mgmt-mock"}


@app.get("/api/assets")
def list_assets():
    return {"code": 0, "message": "success", "data": ASSETS}


@app.post("/api/assets/import")
async def import_assets(request: Request):
    """资产 OpenAPI JSON 导入接口。

    正常请求体示例:
        {"assets": [{"name": "交换机-01", "type": "网络设备"}]}
    """
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(
            status_code=400,
            content={"code": 400, "message": "请求体不是合法 JSON"},
        )

    assets = body.get("assets") if isinstance(body, dict) else None
    if not isinstance(assets, list) or not assets:
        return JSONResponse(
            status_code=400,
            content={"code": 400, "message": "assets 字段缺失或为空列表"},
        )

    for asset in assets:
        if not isinstance(asset, dict) or not str(asset.get("name", "")).strip():
            return JSONResponse(
                status_code=400,
                content={"code": 400, "message": "资产项缺少 name 字段"},
            )
        name = str(asset.get("name", ""))
        if any(ch in name for ch in SPECIAL_CHARS):
            # 已知缺陷：特殊字符未转义导致导入服务内部异常
            return JSONResponse(
                status_code=500,
                content={
                    "code": 500,
                    "message": (
                        "Internal Server Error: 资产名包含未转义的特殊字符，"
                        "导入服务处理失败（已知缺陷，暂不支持 < > & 英文双引号）"
                    ),
                    "asset_name": name,
                },
            )

    return JSONResponse(
        status_code=200,
        content={
            "code": 0,
            "message": "success",
            "data": {
                "imported": len(assets),
                "asset_ids": [f"AST-{2000 + i}" for i in range(len(assets))],
            },
        },
    )


# 静态演示页（Web UI 用例的对象）
app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")
