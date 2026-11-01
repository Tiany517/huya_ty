from typing import Dict, Any
from playwright.async_api import async_playwright
from cli.cookie_manager import CookieManager


class AuthManager:
    """登录管理器：处理扫码/短信登录"""

    def __init__(self, cookie_manager: CookieManager):
        self.cookie_manager = cookie_manager

    async def login(self) -> Dict[str, Any]:
        """启动 headed 浏览器，让用户手动登录，保存 Cookie

        返回 {"success": bool, "message": str}
        """
        if self.cookie_manager.has_cookie():
            return {
                "success": True,
                "message": "Cookie 已存在，如需重新登录请先删除 data/cookie.json"
            }

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=False)
            context = await browser.new_context(
                viewport={"width": 1280, "height": 800},
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            )
            page = await context.new_page()

            try:
                print("正在打开抖音登录页面...")
                await page.goto("https://www.douyin.com/", wait_until="networkidle")

                # 等待用户登录（手动扫码或短信）
                print("请在浏览器中完成登录（扫码或短信）...")
                print("登录完成后按 Enter 键继续...")
                input()  # 等待用户按回车

                # 保存 Cookie
                storage_state = await context.storage_state()
                self.cookie_manager.save_cookie(storage_state)

                return {
                    "success": True,
                    "message": "登录成功，Cookie 已保存"
                }
            except Exception as e:
                return {
                    "success": False,
                    "message": f"登录失败: {str(e)}"
                }
            finally:
                await context.close()
                await browser.close()
