"""
抖音类目搜索抓取器

核心流程：在搜索页 context 中通过 fetch() 调用搜索 API 分页获取用户列表。
DOM 滚动方案对搜索页无效——搜索结果通过 XHR API 分页加载，不是懒加载。

API: /aweme/v1/web/discover/search/
  ?keyword=xxx&search_channel=aweme_user_web&offset=N&count=15

文件位置: cli/scraper.py
"""
import re
import asyncio
import json
import os
from typing import Dict, Any, Set
from playwright.async_api import async_playwright
from models import BloggerItem, CategoryScoutResult
from utils import random_delay, parse_count


class CategoryScraper:
    """类目搜索抓取器 — 使用搜索 API 分页，不进博主主页"""

    def __init__(self, cookie_path: str = None):
        if cookie_path is None:
            cookie_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                "..", "douyin-playwright", "data", "cookie.json",
            )
        self.cookie_path = cookie_path

    async def scrape_category_search(self, keyword: str, max_results: int = 100) -> Dict[str, Any]:
        """
        搜索类目关键词，通过 API 分页抓取 Top N 博主。

        流程：
        1. 打开搜索页（获得 cookie 上下文）
        2. 在页面中用 fetch() 调用搜索 API，逐页获取
        3. 去重、排序、截 Top N
        4. 所有数据来自 API（名称/粉丝数/获赞数/sec_uid），无需 DOM 解析

        Args:
            keyword: 搜索关键词
            max_results: 期望获取的博主数量上限（默认 100）

        Returns:
            CategoryScoutResult.model_dump() 字典
        """
        if not os.path.exists(self.cookie_path):
            return {"error": "COOKIE_NOT_FOUND", "message": f"Cookie 文件不存在: {self.cookie_path}"}

        # 搜索页 URL — 用于建立 cookie 上下文
        search_page_url = f"https://www.douyin.com/search/{keyword}?type=user"

        # 搜索 API base URL
        api_base = (
            "https://www.douyin.com/aweme/v1/web/discover/search/"
            "?device_platform=webapp&aid=6383&channel=channel_pc_web"
            "&search_channel=aweme_user_web"
            f"&keyword={keyword}"
            "&search_source=normal_search&query_correct_type=1&is_filter_search=0"
            "&count=15&pc_client_type=1&version_code=170400&version_name=17.4.0"
            "&cookie_enabled=true&screen_width=1920&screen_height=1080"
        )

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            with open(self.cookie_path, "r", encoding="utf-8") as f:
                storage_state = json.load(f)
            context = await browser.new_context(storage_state=storage_state)
            page = await context.new_page()

            try:
                # 打开搜索页建立上下文
                await page.goto(search_page_url, wait_until="domcontentloaded", timeout=30000)
                await page.wait_for_timeout(3000)

                # 验证码检测
                captcha = await self._detect_captcha(page)
                if captcha["detected"]:
                    if captcha["type"] == "login_expired":
                        return {"error": "COOKIE_EXPIRED", "message": "登录已过期，请重新登录"}
                    elif captcha["type"] == "rate_limit":
                        print("[搜索] 触发频率限制", flush=True)
                    else:
                        resolved = await self._wait_for_captcha(page, timeout=120)
                        if not resolved:
                            return {"error": "CAPTCHA_TIMEOUT", "message": "验证码等待超时"}

                # 逐页抓取（每页一个 fetch，避免 CDP eval 超时）
                all_bloggers = []
                seen_ids: Set[str] = set()
                cursor = 0
                has_more = True
                page_num = 0
                max_pages = (max_results // 15) + 10  # 安全上限

                while has_more and page_num < max_pages and len(all_bloggers) < max_results * 2:
                    page_num += 1

                    # 单页 fetch（带超时保护）
                    fetch_js = f"""
                        (async function() {{
                            try {{
                                var resp = await fetch('{api_base}&offset={cursor}', {{
                                    credentials: 'include',
                                    signal: AbortSignal.timeout(15000)
                                }});
                                var data = await resp.json();
                                return JSON.stringify({{
                                    ok: true,
                                    users: (data.user_list || []).map(function(u) {{
                                        var i = u.user_info || {{}};
                                        return {{
                                            name: i.nickname || '',
                                            fans: i.follower_count || 0,
                                            likes: i.total_favorited || 0,
                                            uid: i.sec_uid || ''
                                        }};
                                    }}),
                                    cursor: data.cursor,
                                    has_more: data.has_more
                                }});
                            }} catch(e) {{
                                return JSON.stringify({{ok: false, err: e.message}});
                            }}
                        }})()
                    """

                    raw = await page.evaluate(fetch_js)
                    data = json.loads(raw)

                    if not data.get("ok"):
                        print(f"[搜索] 第{page_num}页失败: {data.get('err', 'unknown')}", flush=True)
                        break

                    users = data.get("users", [])
                    new_count = 0
                    for u in users:
                        uid = u.get("uid", "")
                        if uid and uid not in seen_ids:
                            seen_ids.add(uid)
                            all_bloggers.append(BloggerItem(
                                blogger_name=u.get("name", ""),
                                fans_count=str(u.get("fans", 0)),
                                fans_count_int=u.get("fans", 0),
                                total_likes=str(u.get("likes", 0)),
                                total_likes_int=u.get("likes", 0),
                                profile_url=f"https://www.douyin.com/user/{uid}",
                            ))
                            new_count += 1

                    cursor = data.get("cursor", 0)
                    has_more = data.get("has_more", False)
                    print(f"[搜索] 第{page_num}页: +{new_count} (累计 {len(all_bloggers)}), has_more={has_more}", flush=True)

                    if new_count == 0:
                        break

                    await asyncio.sleep(1.5)  # 反爬延迟

                # 按粉丝数降序，截 Top N
                all_bloggers.sort(key=lambda x: x.fans_count_int, reverse=True)
                top_bloggers = all_bloggers[:max_results]

                result = CategoryScoutResult(
                    keyword=keyword,
                    total_found=len(all_bloggers),
                    top_100=top_bloggers,
                )
                return result.model_dump()

            except Exception as e:
                return {"error": "SCRAPE_ERROR", "message": f"抓取失败: {str(e)}"}
            finally:
                await context.close()
                await browser.close()

    async def _detect_captcha(self, page) -> Dict[str, Any]:
        """检测验证码"""
        try:
            html = await page.content()
            if "验证" in html or "captcha" in html.lower() or "滑块" in html:
                if "登录" in html and ("过期" in html or "失效" in html):
                    return {"detected": True, "type": "login_expired"}
                if "频繁" in html or "请稍后再试" in html:
                    return {"detected": True, "type": "rate_limit"}
                return {"detected": True, "type": "verify"}
            return {"detected": False, "type": ""}
        except Exception:
            return {"detected": False, "type": ""}

    async def _wait_for_captcha(self, page, timeout: int = 120) -> bool:
        """等待验证码消失（手动解决或自动跳转）"""
        for i in range(timeout // 3):
            await asyncio.sleep(3)
            captcha = await self._detect_captcha(page)
            if not captcha["detected"]:
                print(f"[验证码] 已解除 (等待 {i * 3}s)", flush=True)
                return True
        return False
