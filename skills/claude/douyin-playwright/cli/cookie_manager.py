import json
import os
from pathlib import Path
from typing import Optional, Dict, Any


class CookieManager:
    """Cookie 管理器：保存、加载、验证 Cookie"""

    def __init__(self, cookie_path: str = "data/cookie.json"):
        self.cookie_path = Path(cookie_path)

    def has_cookie(self) -> bool:
        """检查 Cookie 文件是否存在"""
        return self.cookie_path.exists() and self.cookie_path.stat().st_size > 0

    def save_cookie(self, storage_state: Dict[str, Any]) -> None:
        """保存 Playwright storage_state 到文件"""
        self.cookie_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.cookie_path, "w", encoding="utf-8") as f:
            json.dump(storage_state, f, ensure_ascii=False, indent=2)

    def load_cookie(self) -> Optional[Dict[str, Any]]:
        """加载 Cookie 文件"""
        if not self.has_cookie():
            return None
        with open(self.cookie_path, "r", encoding="utf-8") as f:
            return json.load(f)

    async def validate_cookie(self, browser_context) -> Dict[str, Any]:
        """验证 Cookie 是否有效

        打开抖音首页，检查是否已登录。
        返回 {"valid": bool, "message": str}
        """
        page = await browser_context.new_page()
        try:
            await page.goto("https://www.douyin.com/", wait_until="domcontentloaded", timeout=15000)
            await page.wait_for_timeout(2000)

            # 检查是否有登录按钮（未登录标志）
            login_btn = await page.query_selector('a[href*="login"]')
            if login_btn:
                is_visible = await login_btn.is_visible()
                if is_visible:
                    return {"valid": False, "message": "Cookie 已过期，请重新登录"}

            # 检查是否有用户头像（已登录标志）
            avatar = await page.query_selector('[data-e2e="user-avatar"]')
            if avatar:
                return {"valid": True, "message": "Cookie 有效"}

            # 兜底：检查 URL 是否被重定向到登录页
            if "login" in page.url:
                return {"valid": False, "message": "Cookie 已过期，请重新登录"}

            return {"valid": True, "message": "Cookie 看起来有效"}
        except Exception as e:
            return {"valid": False, "message": f"验证失败: {str(e)}"}
        finally:
            await page.close()
