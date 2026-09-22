import pytest
from playwright.sync_api import sync_playwright

import os

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8765")

SCREENSHOT_DIR = __import__("pathlib").Path(__file__).resolve().parents[2] / "screenshots"


@pytest.fixture(scope="session")
def browser():
    with sync_playwright() as p:
        try:
            # 优先使用 Playwright 自带 Chromium
            b = p.chromium.launch(headless=True)
        except Exception:
            # 兜底：使用本机已安装的 Google Chrome（离线环境无需下载浏览器）
            b = p.chromium.launch(channel="chrome", headless=True)
        yield b
        b.close()


@pytest.fixture
def page(browser):
    context = browser.new_context(viewport={"width": 1280, "height": 800})
    pg = context.new_page()
    yield pg
    context.close()


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    rep = outcome.get_result()
    if rep.when == "call" and rep.failed:
        pg = item.funcargs.get("page")
        if pg is not None:
            try:
                SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
                path = SCREENSHOT_DIR / f"{item.name}.png"
                pg.screenshot(path=str(path), full_page=True)
            except Exception:
                pass
