"""汇总接口与 Web 用例的 junit xml，生成 results/report.json 与 results/report.md。

未执行的分组（junit xml 缺失，例如 run.sh 跳过 Web UI 用例）不计入总数，
在报告中标注「未执行」。
"""
import json
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RESULTS_DIR = PROJECT_ROOT / "results"


def parse_suite(xml_path: Path):
    if not xml_path.exists():
        return {
            "total": 0, "passed": 0, "failed": 0, "skipped": 0,
            "duration_sec": 0.0, "failures": [], "executed": False,
        }
    root = ET.parse(xml_path).getroot()
    suites = root.findall(".//testsuite")
    total = failed = errors = skipped = 0
    time_sec = 0.0
    failures = []
    for ts in suites:
        total += int(ts.get("tests", 0))
        failed += int(ts.get("failures", 0))
        errors += int(ts.get("errors", 0))
        skipped += int(ts.get("skipped", 0))
        time_sec += float(ts.get("time", 0.0))
        for tc in ts.findall("testcase"):
            for failure in tc.findall("failure"):
                msg = (failure.get("message") or failure.text or "").strip()
                failures.append({"name": tc.get("name"), "classname": tc.get("classname", ""), "message": msg})
    passed = total - failed - errors - skipped
    return {
        "total": total, "passed": passed, "failed": failed + errors,
        "skipped": skipped, "duration_sec": round(time_sec, 2),
        "failures": failures, "executed": True,
    }


def evidence_for(suite: str, case_name: str):
    """失败证据文件：接口失败 -> logs/api_failures.log；Web 失败 -> screenshots/<用例名>.png"""
    root = PROJECT_ROOT
    if suite == "api":
        log = root / "logs" / "api_failures.log"
        return str(log.relative_to(root)) if log.exists() else None
    shots = sorted((root / "screenshots").glob(f"{case_name}*.png"))
    return str(shots[0].relative_to(root)) if shots else None


def main():
    api = parse_suite(RESULTS_DIR / "api_junit.xml")
    web = parse_suite(RESULTS_DIR / "web_junit.xml")

    executed = [r for r in (api, web) if r["executed"]]
    total = sum(r["total"] for r in executed)
    passed = sum(r["passed"] for r in executed)
    failed = sum(r["failed"] for r in executed)
    rate = f"{passed / total * 100:.2f}%" if total else "0.00%"

    failure_details = []
    for suite, res in (("api", api), ("web", web)):
        for f in res["failures"]:
            failure_details.append({
                "suite": suite,
                "case": f["name"],
                "message": f["message"][:500],
                "evidence": evidence_for(suite, f["name"]),
            })

    report = {
        "title": "中台资产管理平台 自动化测试报告",
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "summary": {"total": total, "passed": passed, "failed": failed, "pass_rate": rate},
        "suites": {
            "api": {k: v for k, v in api.items() if k != "failures"},
            "web": {k: v for k, v in web.items() if k != "failures"},
        },
        "failures": failure_details,
    }

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    (RESULTS_DIR / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    not_executed = [name for name, r in (("web", web), ("api", api)) if not r["executed"]]
    lines = [
        "# 中台资产管理平台 自动化测试报告",
        "",
        f"- 生成时间：{report['generated_at']}",
        f"- 总用例数：**{total}**，通过 **{passed}**，失败 **{failed}**，通过率 **{rate}**",
    ]
    if not_executed:
        lines.append(f"- 注：{'、'.join(s + ' 用例' for s in not_executed)}本次未执行，不计入以上统计")
    lines += [
        "",
        "## 分组统计",
        "",
        "| 分组 | 总数 | 通过 | 失败 | 通过率 | 耗时(s) |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for name, res in (("接口用例 (API)", api), ("Web UI 用例", web)):
        if not res["executed"]:
            lines.append(f"| {name} | - | - | - | 未执行 | - |")
            continue
        r = f"{res['passed'] / res['total'] * 100:.2f}%" if res["total"] else "-"
        lines.append(f"| {name} | {res['total']} | {res['passed']} | {res['failed']} | {r} | {res['duration_sec']} |")
    lines += ["", "## 失败明细", ""]
    if failure_details:
        for f in failure_details:
            lines += [
                f"### [{f['suite']}] {f['case']}",
                "",
                f"- 失败原因：{f['message'].splitlines()[0] if f['message'] else 'N/A'}",
                f"- 证据文件：`{f['evidence'] or '未找到'}`",
                "",
            ]
    else:
        lines.append("无失败用例。")
    (RESULTS_DIR / "report.md").write_text("\n".join(lines), encoding="utf-8")

    print(f"report generated: total={total} passed={passed} failed={failed} pass_rate={rate}")
    return 0 if total else 1


if __name__ == "__main__":
    sys.exit(main())
