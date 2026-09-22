"""接口自动化用例：中台资产管理平台 资产 OpenAPI JSON 导入接口。

共 32 条用例；其中 test_import_name_with_special_chars 为已知缺陷用例，
预期失败（服务端对特殊字符未转义返回 500），失败详情写入 logs/api_failures.log。
"""
import time

import pytest
import requests

from .common import BASE_URL, IMPORT_URL, do_import

# ---------------------------------------------------------------------------
# 1. 服务健康检查
# ---------------------------------------------------------------------------


def test_001_health_check():
    resp = requests.get(f"{BASE_URL}/api/health", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


# ---------------------------------------------------------------------------
# 2~21. 单资产导入（参数化，20 条，全部为正常数据）
# ---------------------------------------------------------------------------

SINGLE_ASSETS = [
    {"name": "核心交换机-SW-01", "type": "网络设备"},
    {"name": "接入交换机-SW-12", "type": "网络设备"},
    {"name": "防火墙-FW-02", "type": "网络设备"},
    {"name": "负载均衡-LB-01", "type": "网络设备"},
    {"name": "数据库服务器-DB-03", "type": "服务器"},
    {"name": "应用服务器-APP-07", "type": "服务器"},
    {"name": "文件服务器-FS-02", "type": "服务器"},
    {"name": "办公笔记本-LT-1024", "type": "终端设备"},
    {"name": "台式机-PC-2048", "type": "终端设备"},
    {"name": "平板电脑-PAD-31", "type": "终端设备"},
    {"name": "打印机-PR-08", "type": "办公设备"},
    {"name": "投影仪-PJ-05", "type": "办公设备"},
    {"name": "视频会议终端-VC-02", "type": "办公设备"},
    {"name": "考勤机-AT-01", "type": "办公设备"},
    {"name": "无线AP-AP-16", "type": "网络设备"},
    {"name": "路由器-RT-04", "type": "网络设备"},
    {"name": "监控摄像头-CAM-09", "type": "安防设备"},
    {"name": "门禁控制器-AC-03", "type": "安防设备"},
    {"name": "UPS电源-UPS-06", "type": "机房设备"},
    {"name": "机柜-RK-11", "type": "机房设备"},
]


@pytest.mark.parametrize("asset", SINGLE_ASSETS)
def test_0xx_import_single_asset(asset):
    """单资产导入：正常资产名 + 类型，应返回 200 且 code=0。"""
    resp = do_import({"assets": [asset]}, testcase=f"test_import_single_asset[{asset['name']}]")
    assert resp.status_code == 200, f"期望 200，实际 {resp.status_code}: {resp.text}"
    body = resp.json()
    assert body["code"] == 0
    assert body["data"]["imported"] == 1


# ---------------------------------------------------------------------------
# 22~31. 批量 / 边界 / 字段覆盖（10 条，全部通过）
# ---------------------------------------------------------------------------


def test_022_import_batch_of_5():
    assets = [{"name": f"批量资产-{i:02d}", "type": "网络设备"} for i in range(1, 6)]
    resp = do_import({"assets": assets}, testcase="test_import_batch_of_5")
    assert resp.status_code == 200
    assert resp.json()["data"]["imported"] == 5


def test_023_import_batch_of_10():
    assets = [{"name": f"批量导入资产-{i:02d}", "type": "终端设备"} for i in range(1, 11)]
    resp = do_import({"assets": assets}, testcase="test_import_batch_of_10")
    assert resp.status_code == 200
    assert resp.json()["data"]["imported"] == 10


def test_024_import_with_all_optional_fields():
    asset = {
        "name": "全字段资产-01",
        "type": "服务器",
        "owner": "研发部",
        "location": "北京机房A",
        "purchase_date": "2026-01-15",
    }
    resp = do_import({"assets": [asset]}, testcase="test_import_with_all_optional_fields")
    assert resp.status_code == 200
    assert resp.json()["code"] == 0


def test_025_import_minimal_fields():
    resp = do_import({"assets": [{"name": "极简资产-01"}]}, testcase="test_import_minimal_fields")
    assert resp.status_code == 200
    assert resp.json()["data"]["imported"] == 1


def test_026_import_chinese_name():
    asset = {"name": "中文命名测试资产·第一号", "type": "办公设备"}
    resp = do_import({"assets": [asset]}, testcase="test_import_chinese_name")
    assert resp.status_code == 200
    assert resp.json()["message"] == "success"


def test_027_import_long_name():
    name = "超长资产名称" + "X" * 100
    resp = do_import({"assets": [{"name": name}]}, testcase="test_import_long_name")
    assert resp.status_code == 200
    assert resp.json()["data"]["imported"] == 1


def test_028_import_name_with_spaces():
    resp = do_import({"assets": [{"name": "资产 名称 带空格"}]}, testcase="test_import_name_with_spaces")
    assert resp.status_code == 200


def test_029_import_name_with_hyphen_and_digits():
    resp = do_import(
        {"assets": [{"name": "Router-2026-Core-01", "type": "网络设备"}]},
        testcase="test_import_name_with_hyphen_and_digits",
    )
    assert resp.status_code == 200


def test_030_import_returns_asset_ids():
    assets = [{"name": f"编号校验资产-{i}"} for i in range(1, 4)]
    resp = do_import({"assets": assets}, testcase="test_import_returns_asset_ids")
    assert resp.status_code == 200
    ids = resp.json()["data"]["asset_ids"]
    assert len(ids) == 3 and all(i.startswith("AST-") for i in ids)


def test_031_import_response_code_zero():
    resp = do_import({"assets": [{"name": "响应码校验资产"}]}, testcase="test_import_response_code_zero")
    assert resp.status_code == 200
    assert resp.json()["code"] == 0
    assert resp.json()["message"] == "success"


# ---------------------------------------------------------------------------
# 32. 已知缺陷用例（预期失败）：特殊字符资产名导入
# ---------------------------------------------------------------------------


def test_032_import_name_with_special_chars():
    """已知缺陷：资产名包含 < > & 英文双引号 时导入服务未转义，返回 HTTP 500。

    该用例预期 200，实际服务返回 500 —— 用于演示缺陷；失败详情见 logs/api_failures.log。
    """
    asset = {"name": '核心"交换机" <骨干> &防火墙', "type": "网络设备"}
    resp = do_import({"assets": [asset]}, testcase="test_032_import_name_with_special_chars")
    assert resp.status_code == 200, (
        f"已知缺陷复现：资产名含特殊字符时导入返回 {resp.status_code}，"
        f"响应体: {resp.text}（证据见 logs/api_failures.log）"
    )
