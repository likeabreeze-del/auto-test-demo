"""Web UI 自动化用例：中台资产管理平台静态演示页（共 16 条，预期全部通过）。"""
import re

from .conftest import BASE_URL

INDEX = f"{BASE_URL}/index.html"
ASSETS = f"{BASE_URL}/assets.html"
IMPORT = f"{BASE_URL}/import.html"


# --------------------------- 首页（5 条） ---------------------------


def test_w01_index_page_title(page):
    page.goto(INDEX)
    assert "中台资产管理平台" in page.title()


def test_w02_index_h1_text(page):
    page.goto(INDEX)
    assert page.locator("h1").inner_text() == "中台资产管理平台"


def test_w03_index_nav_link_count(page):
    page.goto(INDEX)
    assert page.locator("nav a").count() == 3


def test_w04_index_nav_to_assets(page):
    page.goto(INDEX)
    link = page.locator("nav a", has_text="资产列表")
    assert link.get_attribute("href") == "/assets.html"


def test_w05_index_footer_text(page):
    page.goto(INDEX)
    footer = page.locator("footer").inner_text()
    assert "Mock 演示环境" in footer


# --------------------------- 资产列表页（6 条） ---------------------------


def test_w06_assets_page_title(page):
    page.goto(ASSETS)
    assert "资产列表" in page.title()


def test_w07_assets_table_row_count(page):
    page.goto(ASSETS)
    assert page.locator("#asset-table tbody tr").count() == 5


def test_w08_assets_search_input(page):
    page.goto(ASSETS)
    search = page.locator("#search")
    assert search.is_visible()
    assert "按资产名称搜索" in search.get_attribute("placeholder")


def test_w09_assets_table_headers(page):
    page.goto(ASSETS)
    headers = page.locator("#asset-table thead th").all_inner_texts()
    assert headers == ["资产ID", "资产名称", "类型", "状态"]


def test_w10_assets_first_row_name(page):
    page.goto(ASSETS)
    assert page.locator("#asset-table tbody tr").first.locator("td").nth(1).inner_text() == "核心交换机-SW-01"


def test_w11_assets_first_status_badge(page):
    page.goto(ASSETS)
    assert page.locator("#asset-table tbody tr").first.locator(".badge").inner_text() == "运行中"


# --------------------------- 资产导入页（5 条） ---------------------------


def test_w12_import_page_title(page):
    page.goto(IMPORT)
    assert "资产导入" in page.title()


def test_w13_import_name_input(page):
    page.goto(IMPORT)
    name_input = page.locator("#asset-name")
    assert name_input.is_visible()
    assert name_input.get_attribute("placeholder") == "请输入资产名称"


def test_w14_import_type_options(page):
    page.goto(IMPORT)
    options = page.locator("#asset-type option").all_inner_texts()
    assert options == ["网络设备", "服务器", "终端设备", "办公设备"]


def test_w15_import_submit_button(page):
    page.goto(IMPORT)
    assert page.locator("#submit-btn").inner_text() == "开始导入"


def test_w16_import_tip_mentions_special_chars(page):
    page.goto(IMPORT)
    tip = page.locator("#tip").inner_text()
    assert re.search(r"特殊字符", tip) and "已知缺陷" in tip
