"""自动从浏览器提取抖音 Cookie 并写入 settings.json"""

import json
import os

import browser_cookie3

SETTINGS_PATH = os.path.join(
    os.path.expanduser("~"),
    "TikTokDownloader",
    "Volume",
    "settings.json",
)


def extract_douyin_cookie():
    """从 Chrome/Edge 等浏览器提取 douyin.com 的 Cookie"""
    cookie_str = ""

    # 依次尝试不同浏览器
    browsers = [
        ("Chrome", browser_cookie3.chrome),
        ("Edge", browser_cookie3.edge),
        ("Firefox", browser_cookie3.firefox),
    ]

    for browser_name, cookie_func in browsers:
        try:
            cj = cookie_func(domain_name=".douyin.com")
            cookies = list(cj)
            if cookies:
                print(f"从 {browser_name} 找到 {len(cookies)} 个抖音 Cookie")
                # 组合成 Cookie 字符串
                parts = [f"{c.name}={c.value}" for c in cookies]
                cookie_str = "; ".join(parts)
                return cookie_str, browser_name
        except Exception as e:
            print(f"{browser_name} 提取失败: {e}")
            continue

    return "", None


def write_cookie_to_settings(cookie_str: str):
    """将 Cookie 写入 settings.json"""
    try:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
            settings = json.load(f)

        settings["cookie"] = cookie_str

        with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=4, ensure_ascii=False)

        print(f"Cookie 已写入 {SETTINGS_PATH}")
        return True
    except Exception as e:
        print(f"写入 settings.json 失败: {e}")
        return False


def main():
    print("正在从浏览器提取抖音 Cookie...\n")
    cookie_str, browser_name = extract_douyin_cookie()

    if cookie_str:
        print(f"\n成功从 {browser_name} 提取到抖音 Cookie!")
        print(f"Cookie 长度: {len(cookie_str)} 字符")
        write_cookie_to_settings(cookie_str)
    else:
        print("\n未能从任何浏览器提取到抖音 Cookie")
        print("可能的原因:")
        print("  1. 你没有在浏览器中登录抖音")
        print("  2. 浏览器 Cookie 数据库被加密/锁定（浏览器正在运行时可能出现）")
        print("\n请手动操作:")
        print("  1. 用浏览器打开 douyin.com 并登录")
        print("  2. 按F12打开开发者工具 → Application → Cookies → douyin.com")
        print("  3. 复制所有cookie内容")


if __name__ == "__main__":
    main()
