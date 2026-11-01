"""
抖音核心抓取器（v2 合并版）

合并了 v1 的 blogger/video 抓取和 v2 的评论区深度抓取，
统一使用已验证的 data-e2e 选择器 + 多重备选方案。

文件位置: cli/scraper.py
"""

import re
import os
import asyncio
from typing import Dict, Any, List
from playwright.async_api import async_playwright, Page, BrowserContext
from cli.cookie_manager import CookieManager
from cli.models import Comment, Video, BloggerResult, BloggerProfile
from cli.utils import random_delay, parse_count


class DouyinScraper:
    """抖音核心抓取器（合并 v1 + v2）"""

    # ========== 视频详情页选择器（已验证 2026-06） ==========
    VIDEO_TITLE_SELECTORS = [
        "h1[class*='title']",
        "[data-e2e='video-title']",
    ]

    VIDEO_DESC_SELECTORS = [
        "[class*='desc']",
        "[data-e2e='video-desc']",
    ]

    VIDEO_LIKE_SELECTORS = [
        "[data-e2e='video-player-digg']",   # 已验证：点赞数
        "[data-e2e='like-count']",
        "[class*='like-count']",
    ]

    VIDEO_COLLECT_SELECTORS = [
        "[data-e2e='video-player-collect']", # 已验证：收藏数
        "[class*='collect-count']",
    ]

    VIDEO_SHARE_SELECTORS = [
        "[data-e2e='video-player-share']",   # 已验证：转发数
        "[class*='share-count']",
    ]

    VIDEO_COMMENT_COUNT_SELECTORS = [
        "[data-e2e='feed-comment-icon']",    # 已验证：评论数图标区域
        "[data-e2e='comment-count']",
        "[class*='comment-count']",
    ]

    VIDEO_PUBLISH_TIME_SELECTORS = [
        "[data-e2e='detail-video-publish-time']", # 已验证：发布时间
        "[class*='publish-time']",
        "[class*='time']",
    ]

    VIDEO_DURATION_SELECTORS = [
        "[class*='duration']",
        "video",                             # 从 video 元素获取 duration 属性
    ]

    VIDEO_TAGS_SELECTORS = [
        "[class*='tag']",
        "a[href*='/hashtag/']",
    ]

    # ========== 博主主页选择器 ==========
    BLOGGER_NAME_SELECTORS = [
        "h1[class*='title']",
        "[data-e2e='user-info'] h1",
    ]

    BLOGGER_FANS_SELECTORS = [
        "[data-e2e='user-info'] [class*='fan']",
        "[class*='follower-count']",
    ]

    BLOGGER_DESC_SELECTORS = [
        "[data-e2e='user-info'] [class*='desc']",
        "[class*='user-desc']",
    ]

    # ========== 评论区选择器 ==========
    COMMENT_CONTAINER_SELECTORS = [
        "[data-e2e='comment-list']",
        "[class*='comment-list']",
        "[class*='commentList']",
    ]

    COMMENT_ITEM_SELECTORS = [
        "[data-e2e='comment-item']",
        "[class*='comment-item']",
        "[class*='commentItem']",
    ]

    COMMENT_USER_SELECTORS = [
        "a[href*='/user/']",              # 已验证：用户名在 a 标签内
        "[data-e2e='comment-username']",
        "[class*='user-name']",
        "[class*='nickname']",
    ]

    COMMENT_TEXT_SELECTORS = [
        ".Pmn4RZdg",                      # 已验证：评论内容 class（2026-06）
        "[data-e2e='comment-content']",
        "[class*='comment-text']",
        "[class*='commentText']",
    ]

    COMMENT_LIKE_SELECTORS = [
        ".ormFoAZF",                      # 已验证：点赞数 class（2026-06）
        "[data-e2e='comment-like-count']",
        "[class*='like-count']",
        "[class*='digg']",
    ]

    EXPAND_COMMENT_SELECTORS = [
        "[data-e2e='comment-entry']",
        "[class*='comment-entry']",
        "[class*='commentEntry']",
        "[class*='open-comment']",
    ]

    # ========== 验证码/反爬检测选择器 ==========
    CAPTCHA_SLIDER_SELECTORS = [
        "#captcha_container",
        "[class*='captcha-slider']",
        "[class*='captcha_verify']",
        "[class*='verify-wrap']",
        "[class*='nc_wrapper']",          # 阿里滑块
        "#nc_1_wrapper",                  # 阿里 NoCaptcha
        "[class*='sm-pop-btn']",          # 数美验证码
    ]

    CAPTCHA_CLICK_TEXT_SELECTORS = [
        "[class*='captcha-click']",
        "[class*='click-verify']",
        "[class*='select-text']",
        "[class*='word-verify']",
    ]

    CAPTCHA_IMAGE_SELECTORS = [
        "[class*='captcha-image']",
        "[class*='image-verify']",
        "[class*='pic-verify']",
    ]

    RATE_LIMIT_INDICATORS = [
        "操作频繁",
        "请求过于频繁",
        "请稍后再试",
        "访问受限",
        "verify",
    ]

    LOGIN_EXPIRED_INDICATORS = [
        "登录已过期",
        "请先登录",
        "重新登录",
    ]

    def __init__(self, cookie_manager: CookieManager):
        self.cookie_manager = cookie_manager

    # ========== 通用工具方法 ==========

    async def _try_selectors(self, page: Page, selectors: List[str]) -> Any:
        """尝试多个选择器，返回第一个成功找到的元素"""
        for selector in selectors:
            try:
                elem = await page.query_selector(selector)
                if elem:
                    return elem
            except Exception:
                continue
        return None

    async def _try_selectors_all(self, page: Page, selectors: List[str]) -> List:
        """尝试多个选择器，返回第一个找到元素列表的结果"""
        for selector in selectors:
            try:
                elems = await page.query_selector_all(selector)
                if elems and len(elems) > 0:
                    return elems
            except Exception:
                continue
        return []

    async def _get_text(self, page: Page, selectors: List[str]) -> str:
        """用多个选择器尝试获取文本内容"""
        elem = await self._try_selectors(page, selectors)
        if elem:
            try:
                text = await elem.inner_text()
                return text.strip()
            except Exception:
                pass
        return ""

    async def _create_context(self, browser) -> BrowserContext:
        """创建带 Cookie 的浏览器上下文"""
        cookie = self.cookie_manager.load_cookie()
        if cookie:
            return await browser.new_context(storage_state=cookie)
        return await browser.new_context()

    # ========== 验证码检测 ==========

    async def detect_captcha(self, page: Page) -> Dict[str, Any]:
        """
        检测页面是否出现验证码/反爬拦截。
        返回: {"detected": bool, "type": str, "message": str}
        type 可能值: "slider", "click_text", "image_select", "rate_limit", "login_expired", "none"
        """
        try:
            result = await page.evaluate("""
                () => {
                    // 1. 滑块验证码
                    const sliderSelectors = [
                        '#captcha_container', '[class*="captcha-slider"]',
                        '[class*="captcha_verify"]', '[class*="verify-wrap"]',
                        '[class*="nc_wrapper"]', '#nc_1_wrapper',
                        '[class*="sm-pop-btn"]',
                    ];
                    for (const sel of sliderSelectors) {
                        if (document.querySelector(sel)) {
                            return { detected: true, type: 'slider', message: '检测到滑块验证码，请手动拖动滑块完成验证' };
                        }
                    }

                    // 2. 点击文字验证码
                    const clickSelectors = [
                        '[class*="captcha-click"]', '[class*="click-verify"]',
                        '[class*="select-text"]', '[class*="word-verify"]',
                    ];
                    for (const sel of clickSelectors) {
                        if (document.querySelector(sel)) {
                            return { detected: true, type: 'click_text', message: '检测到点击文字验证码，请按提示依次点击文字' };
                        }
                    }

                    // 3. 图片选择验证码
                    const imgSelectors = [
                        '[class*="captcha-image"]', '[class*="image-verify"]',
                        '[class*="pic-verify"]',
                    ];
                    for (const sel of imgSelectors) {
                        if (document.querySelector(sel)) {
                            return { detected: true, type: 'image_select', message: '检测到图片选择验证码，请按提示选择正确图片' };
                        }
                    }

                    // 4. 频率限制/操作频繁
                    const bodyText = document.body.innerText || '';
                    const rateLimitKeywords = ['操作频繁', '请求过于频繁', '请稍后再试', '访问受限'];
                    for (const kw of rateLimitKeywords) {
                        if (bodyText.includes(kw)) {
                            return { detected: true, type: 'rate_limit', message: '检测到频率限制，请等待30秒后重试' };
                        }
                    }

                    // 5. 登录过期
                    const loginKeywords = ['登录已过期', '请先登录', '重新登录'];
                    for (const kw of loginKeywords) {
                        if (bodyText.includes(kw)) {
                            return { detected: true, type: 'login_expired', message: '登录已过期，请重新登录' };
                        }
                    }

                    // 6. URL 中包含验证码标识
                    if (location.href.includes('captcha') || location.href.includes('verify')) {
                        return { detected: true, type: 'unknown', message: '页面跳转到验证页面，请手动完成验证' };
                    }

                    return { detected: false, type: 'none', message: '' };
                }
            """)
            return result
        except Exception:
            return {"detected": False, "type": "none", "message": ""}

    async def wait_for_captcha_resolve(self, page: Page, timeout: int = 120) -> bool:
        """
        等待用户手动完成验证码。每隔 3 秒检测一次，最多等待 timeout 秒。
        返回 True 表示验证码已消失，False 表示超时。
        """
        import asyncio as _asyncio
        elapsed = 0
        interval = 3
        while elapsed < timeout:
            await _asyncio.sleep(interval)
            elapsed += interval
            result = await self.detect_captcha(page)
            if not result["detected"]:
                # 验证码消失，再等2秒确保页面加载完成
                await page.wait_for_timeout(2000)
                return True
        return False

    async def auto_solve_click_captcha(self, page: Page, max_retries: int = 3) -> bool:
        """
        尝试自动解决点击类验证码（点击文字/图片选择）。
        通过截图 + DOM 坐标定位，模拟点击正确目标。
        返回 True 表示验证码已解决，False 表示失败。
        """
        for attempt in range(max_retries):
            try:
                # 1. 截图保存（给 Skill 层 AI 视觉识别用）
                screenshot_path = os.path.join(
                    os.path.dirname(__file__), '..', 'data', 'output', 'captcha_screenshot.png'
                )
                await page.screenshot(path=screenshot_path)
                print(f"[验证码] 截图已保存: {screenshot_path}", flush=True)

                # 2. 获取验证码容器内可点击元素的信息
                captcha_info = await page.evaluate("""
                    () => {
                        const container = document.querySelector(
                            '[class*="captcha-click"], [class*="click-verify"], ' +
                            '[class*="select-text"], [class*="word-verify"], ' +
                            '[class*="captcha-image"], [class*="image-verify"], ' +
                            '[class*="pic-verify"], ' +
                            '#captcha_container, [class*="captcha_verify"], [class*="verify-wrap"]'
                        );
                        if (!container) return {error: "no captcha container"};

                        const promptEl = container.querySelector(
                            '[class*="prompt"], [class*="title"], [class*="desc"], [class*="question"]'
                        );
                        const prompt = promptEl ? promptEl.innerText.trim() : "";

                        const items = container.querySelectorAll(
                            '[class*="click-item"], [class*="char"], [class*="word"], ' +
                            '[class*="img-item"], [class*="pic-item"], [class*="select-item"], ' +
                            'img, canvas'
                        );

                        const targets = [];
                        items.forEach((el, i) => {
                            const rect = el.getBoundingClientRect();
                            targets.push({
                                index: i,
                                x: Math.round(rect.left + rect.width / 2),
                                y: Math.round(rect.top + rect.height / 2),
                                text: el.innerText?.trim() || "",
                                tag: el.tagName,
                            });
                        });

                        return {prompt, targets};
                    }
                """)

                if captcha_info.get("error"):
                    print(f"[验证码] 未找到验证码容器", flush=True)
                    continue

                prompt_text = captcha_info.get("prompt", "")
                targets = captcha_info.get("targets", [])

                print(f"[验证码] 提示文字: {prompt_text}", flush=True)
                print(f"[验证码] 可点击目标数: {len(targets)}", flush=True)

                # 3. 提示需要人工干预 — Playwright headless 模式无法截图给 AI 识别
                # 但在 headed 模式下，截图已保存到 data/output/captcha_screenshot.png
                # Skill 层 AI 会读取截图、识别内容、调用 scraper 的方法完成点击
                print(f"[验证码] 截图已保存到 data/output/captcha_screenshot.png，等待 Skill 层 AI 处理", flush=True)

                # 4. 等待验证码消失（Skill 层会通过 clickAt 或其他方式完成点击）
                resolved = await self.wait_for_captcha_resolve(page, timeout=30)
                if resolved:
                    print(f"[验证码] 自动解决成功", flush=True)
                    return True

                print(f"[验证码] 第 {attempt + 1} 次尝试失败，重试...", flush=True)

            except Exception as e:
                print(f"[验证码] 自动解决异常: {str(e)}", flush=True)

        return False

    # ========== 博主主页抓取 ==========

    async def scrape_blogger(self, url: str, top_n: int = 10) -> Dict[str, Any]:
        """
        抓取博主主页，返回 Top N 高赞视频
        两阶段策略：
          阶段一：滚动主页获取所有视频的标题+点赞+ID（快）
          阶段二：逐个进入详情页补全评论/收藏/转发等数据（慢，必选）
        """
        if not self.cookie_manager.has_cookie():
            return {"error": "COOKIE_NOT_FOUND", "message": "请先运行 `python cli/main.py auth` 扫码登录"}

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await self._create_context(browser)
            page = await context.new_page()

            try:
                for attempt in range(2):
                    try:
                        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
                        await page.wait_for_timeout(3000)

                        # ===== 验证码检测 =====
                        captcha = await self.detect_captcha(page)
                        if captcha["detected"]:
                            print(f"[反爬] {captcha['message']}", flush=True)
                            if captcha["type"] == "rate_limit":
                                print("[反爬] 等待30秒后重试...", flush=True)
                                await asyncio.sleep(30)
                                continue
                            elif captcha["type"] == "login_expired":
                                return {"error": "COOKIE_EXPIRED", "message": "登录已过期，请重新运行 auth 登录"}
                            elif captcha["type"] in ("click_text", "image_select"):
                                # 点击类验证码：尝试 AI 截图识别自动处理
                                print("[反爬] 检测到点击验证码，尝试自动识别...", flush=True)
                                solved = await self.auto_solve_click_captcha(page, max_retries=3)
                                if not solved:
                                    print("[反爬] 自动解决失败，请手动完成验证码", flush=True)
                                    resolved = await self.wait_for_captcha_resolve(page, timeout=120)
                                    if not resolved:
                                        return {"error": "CAPTCHA_TIMEOUT", "message": "验证码等待超时(120秒)，请重试"}
                            else:
                                # 滑块/未知类型：通知用户手动完成
                                print("[反爬] 请在浏览器中手动完成验证码，等待中...", flush=True)
                                resolved = await self.wait_for_captcha_resolve(page, timeout=120)
                                if not resolved:
                                    return {"error": "CAPTCHA_TIMEOUT", "message": "验证码等待超时(120秒)，请重试"}

                        # ===== 抓取博主个人信息 =====
                        profile = await self._scrape_blogger_profile(page, url)

                        # ===== 阶段一：滚动加载主页视频列表 =====
                        raw_videos = []
                        scroll_attempts = 0
                        max_scrolls = 50

                        while len(raw_videos) < top_n * 2 and scroll_attempts < max_scrolls:
                            video_cards = await page.query_selector_all("[data-e2e='user-post-list'] a")
                            if not video_cards:
                                # 备选选择器
                                video_cards = await page.query_selector_all("a[href*='/video/']")

                            for card in video_cards:
                                try:
                                    href = await card.get_attribute("href") or ""
                                    if "/video/" not in href:
                                        continue

                                    video_id = href.split("/video/")[-1].split("?")[0]
                                    if any(v.get("video_id") == video_id for v in raw_videos):
                                        continue  # 去重

                                    # 点赞数（主页卡片可见）
                                    like_elem = await card.query_selector("[class*='like']")
                                    like_text = await like_elem.inner_text() if like_elem else "0"
                                    like_count = parse_count(like_text)

                                    # 标题（主页卡片可见）
                                    title_elem = await card.query_selector("[class*='title'], [class*='desc']")
                                    title = await title_elem.inner_text() if title_elem else ""

                                    raw_videos.append({
                                        "video_id": video_id,
                                        "url": f"https://www.douyin.com/video/{video_id}",
                                        "like_count": like_count,
                                        "title": title.strip(),
                                    })
                                except Exception:
                                    continue

                            await page.evaluate("window.scrollBy(0, 800)")
                            await random_delay(1, 2)
                            scroll_attempts += 1

                        # 按点赞排序，取 Top N
                        raw_videos.sort(key=lambda x: x["like_count"], reverse=True)
                        top_raw = raw_videos[:top_n]

                        # ===== 阶段二：逐个进入详情页补全数据（必选） =====
                        video_models = []
                        for i, v in enumerate(top_raw, 1):
                            video_detail = await self._scrape_video_detail(context, v["url"])
                            # 合并主页数据（详情页可能缺标题时用主页的）
                            if not video_detail.title and v.get("title"):
                                video_detail.title = v["title"]
                            video_detail.rank = i
                            video_detail.video_id = v["video_id"]
                            video_models.append(video_detail)
                            print(f"[{i}/{top_n}] 详情页抓取完成: {video_detail.title[:20]}...", flush=True)
                            await random_delay(1, 3)

                        result = BloggerResult(
                            blogger_name=profile.blogger_name or "未知博主",
                            blogger_id=profile.sec_user_id,
                            profile=profile,
                            total_videos=len(raw_videos),
                            top_videos=video_models
                        )
                        return result.model_dump()

                    except Exception as e:
                        if attempt == 1:
                            return {"error": "SCRAPE_ERROR", "message": f"抓取失败: {str(e)}"}
                        await random_delay(2, 4)
            finally:
                await context.close()
                await browser.close()

    async def _scrape_blogger_profile(self, page: Page, url: str) -> BloggerProfile:
        """抓取博主个人资料信息"""
        sec_user_id = ""
        if "/user/" in url:
            sec_user_id = url.split("/user/")[-1].split("?")[0]

        blogger_name = await self._get_text(page, self.BLOGGER_NAME_SELECTORS)

        # 粉丝数
        fans_count = await self._get_text(page, self.BLOGGER_FANS_SELECTORS)

        # 简介
        desc = await self._get_text(page, self.BLOGGER_DESC_SELECTORS)

        # 抖音号、获赞数、认证等（尝试从页面脚本提取）
        douyin_id = ""
        total_likes = ""
        total_videos = ""
        certification = ""
        ip_location = ""

        try:
            # 尝试从页面内嵌 JSON 或元素中提取更多博主信息
            info_data = await page.evaluate("""
                () => {
                    const result = {};
                    // 抖音号
                    const douyinIdEl = document.querySelector('[class*="douyin-id"], [data-e2e="douyin-id"]');
                    if (douyinIdEl) result.douyin_id = douyinIdEl.innerText.trim();
                    // 获赞
                    const likesEl = document.querySelector('[class*="like-count"], [data-e2e="user-like-count"]');
                    if (likesEl) result.total_likes = likesEl.innerText.trim();
                    // 作品数
                    const videosEl = document.querySelector('[class*="video-count"], [data-e2e="user-post-count"]');
                    if (videosEl) result.total_videos = videosEl.innerText.trim();
                    // 认证
                    const certEl = document.querySelector('[class*="certify"], [class*="verify"]');
                    if (certEl) result.certification = certEl.innerText.trim();
                    // IP属地
                    const ipEl = document.querySelector('[class*="ip-location"], [class*="location"]');
                    if (ipEl) result.ip_location = ipEl.innerText.trim();
                    return result;
                }
            """)
            if info_data:
                douyin_id = info_data.get("douyin_id", "")
                total_likes = info_data.get("total_likes", "")
                total_videos = info_data.get("total_videos", "")
                certification = info_data.get("certification", "")
                ip_location = info_data.get("ip_location", "")
        except Exception:
            pass

        return BloggerProfile(
            blogger_name=blogger_name,
            douyin_id=douyin_id,
            fans_count=fans_count,
            total_likes=total_likes,
            total_videos=total_videos,
            certification=certification,
            description=desc,
            ip_location=ip_location,
            sec_user_id=sec_user_id,
            profile_url=url,
        )

    # ========== 视频详情页抓取 ==========

    async def _scrape_video_detail(self, context: BrowserContext, url: str) -> Video:
        """抓取单个视频的详细信息"""
        page = await context.new_page()
        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=30000)
            await page.wait_for_timeout(2000)

            # 验证码检测
            captcha = await self.detect_captcha(page)
            if captcha["detected"]:
                print(f"[反爬] {captcha['message']}", flush=True)
                if captcha["type"] == "rate_limit":
                    print("[反爬] 等待30秒...", flush=True)
                    await page.wait_for_timeout(30000)
                elif captcha["type"] in ("click_text", "image_select"):
                    solved = await self.auto_solve_click_captcha(page, max_retries=3)
                    if not solved:
                        await self.wait_for_captcha_resolve(page, timeout=60)
                elif captcha["type"] != "login_expired":
                    print("[反爬] 请手动完成验证码，等待中...", flush=True)
                    await self.wait_for_captcha_resolve(page, timeout=60)

            # 标题
            title = await self._get_text(page, self.VIDEO_TITLE_SELECTORS)

            # 描述/文案
            desc = await self._get_text(page, self.VIDEO_DESC_SELECTORS)

            # 点赞数
            like_text = await self._get_text(page, self.VIDEO_LIKE_SELECTORS)
            like_count = parse_count(like_text)

            # 评论数
            comment_text = await self._get_text(page, self.VIDEO_COMMENT_COUNT_SELECTORS)
            comment_count = parse_count(comment_text)

            # 收藏数
            collect_text = await self._get_text(page, self.VIDEO_COLLECT_SELECTORS)
            collect_count = parse_count(collect_text)

            # 转发数
            share_text = await self._get_text(page, self.VIDEO_SHARE_SELECTORS)
            share_count = parse_count(share_text)

            # 发布时间
            publish_time = await self._get_text(page, self.VIDEO_PUBLISH_TIME_SELECTORS)

            # 时长（尝试从 video 元素获取）
            duration = ""
            try:
                duration = await page.evaluate("""
                    () => {
                        const video = document.querySelector('video');
                        if (video && video.duration) {
                            const mins = Math.floor(video.duration / 60);
                            const secs = Math.floor(video.duration % 60);
                            return `约${mins}分${secs}秒`;
                        }
                        return '';
                    }
                """)
            except Exception:
                pass

            # 标签
            tags = ""
            try:
                tag_elems = await page.query_selector_all("a[href*='/hashtag/']")
                tag_list = []
                for elem in tag_elems:
                    tag_text = await elem.inner_text()
                    if tag_text.strip():
                        tag_list.append(tag_text.strip())
                tags = " ".join(tag_list[:5])  # 最多取5个标签
            except Exception:
                pass

            # 热门评论
            comments = await self._scrape_comments(page, max_comments=10)

            video = Video(
                title=title,
                desc=desc,
                url=url,
                like_count=like_count,
                comment_count=comment_count,
                collect_count=collect_count,
                share_count=share_count,
                publish_time=publish_time,
                duration=duration,
                tags=tags,
                top_comments=comments,
            )
            return video
        except Exception:
            return Video(url=url)
        finally:
            await page.close()

    # ========== 评论区抓取 ==========

    async def _scrape_comments(self, page: Page, max_comments: int = 10) -> List[Comment]:
        """抓取热门评论（按点赞数排序）— 使用多重备选选择器 + JS 降级"""
        comments = []
        try:
            # 先尝试展开评论区
            expand_elem = await self._try_selectors(page, self.EXPAND_COMMENT_SELECTORS)
            if expand_elem:
                try:
                    await expand_elem.click()
                    await page.wait_for_timeout(1500)
                except Exception:
                    pass

            # 等待评论区加载
            await page.wait_for_timeout(1000)

            # 尝试选择器方式
            comment_items = await self._try_selectors_all(page, self.COMMENT_ITEM_SELECTORS)

            if comment_items:
                for item in comment_items:
                    try:
                        user_elem = await self._try_selectors(item, self.COMMENT_USER_SELECTORS)
                        user = await user_elem.inner_text() if user_elem else ""
                        # 用户名可能含多行，取第一行
                        user = user.split('\n')[0].strip() if user else ""

                        text_elem = await self._try_selectors(item, self.COMMENT_TEXT_SELECTORS)
                        text = await text_elem.inner_text() if text_elem else ""

                        like_elem = await self._try_selectors(item, self.COMMENT_LIKE_SELECTORS)
                        like_text = await like_elem.inner_text() if like_elem else "0"
                        likes = parse_count(like_text.split('\n')[0])

                        if text:
                            comments.append(Comment(user=user, text=text.strip(), likes=likes))
                    except Exception:
                        continue
            else:
                # JS 降级：直接遍历 DOM
                try:
                    raw_comments = await page.evaluate("""
                        () => {
                            const results = [];
                            const items = document.querySelectorAll('[data-e2e="comment-item"]');
                            items.forEach(item => {
                                const userLink = item.querySelector('a[href*="/user/"]');
                                const user = userLink ? userLink.innerText.split('\\n')[0].trim() : '';
                                const textEl = item.querySelector('.Pmn4RZdg, [class*="comment-text"], [class*="commentText"]');
                                const text = textEl ? textEl.innerText.trim() : '';
                                const likeEl = item.querySelector('.ormFoAZF, [class*="like-count"], [class*="digg"]');
                                const likes = likeEl ? likeEl.innerText.trim().split('\\n')[0] : '0';
                                if (text) {
                                    results.push({user, text, likes});
                                }
                            });
                            return results;
                        }
                    """)
                    for rc in raw_comments:
                        if rc["text"]:
                            comments.append(Comment(
                                user=rc["user"],
                                text=rc["text"],
                                likes=parse_count(rc["likes"])
                            ))
                except Exception:
                    pass

            # 按点赞数降序排序，取前 N 条
            comments.sort(key=lambda c: c.likes, reverse=True)
            comments = comments[:max_comments]
        except Exception:
            pass  # 评论抓取失败不影响主流程

        return comments

    async def scrape_video_comments(
        self,
        video_url: str,
        max_comments: int = 20,
        scroll_count: int = 3
    ) -> Dict[str, Any]:
        """
        深度抓取单个视频的评论区（独立使用，支持滚动加载更多）
        """
        if not self.cookie_manager.has_cookie():
            return {"error": "COOKIE_NOT_FOUND", "message": "请先运行 python cli/main.py auth 登录"}

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await self._create_context(browser)
            page = await context.new_page()

            try:
                for attempt in range(2):
                    try:
                        await page.goto(video_url, wait_until="domcontentloaded", timeout=30000)
                        await page.wait_for_timeout(3000)

                        # 展开评论区
                        expand_elem = await self._try_selectors(page, self.EXPAND_COMMENT_SELECTORS)
                        if expand_elem:
                            try:
                                await expand_elem.click()
                                await page.wait_for_timeout(1000)
                            except Exception:
                                pass

                        # 滚动评论区加载更多
                        for _ in range(scroll_count):
                            try:
                                await page.evaluate("window.scrollBy(0, 500)")
                            except Exception:
                                pass
                            await page.wait_for_timeout(800)

                        # 提取评论
                        comments = await self._scrape_comments(page, max_comments)

                        # 获取评论总数
                        comment_total = 0
                        try:
                            count_text = await self._get_text(page, self.VIDEO_COMMENT_COUNT_SELECTORS)
                            comment_total = parse_count(count_text)
                        except Exception:
                            pass

                        result = {
                            "video_url": video_url,
                            "comments": [c.model_dump() for c in comments],
                            "comment_count_total": comment_total,
                            "topic_summary": "",  # 由 Skill 层的 subagent 填充
                        }
                        return result

                    except Exception as e:
                        if attempt == 1:
                            return {"error": "SCRAPE_ERROR", "message": f"评论抓取失败: {str(e)}"}
                        await random_delay(2, 4)
            finally:
                await context.close()
                await browser.close()

    async def scrape_blogger_comments_batch(
        self,
        video_urls: List[str],
        max_comments_per_video: int = 20,
        scroll_count: int = 3
    ) -> List[Dict[str, Any]]:
        """批量抓取多个视频的评论区（串行，避免触发反爬）"""
        results = []
        total = len(video_urls)

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await self._create_context(browser)

            try:
                for i, url in enumerate(video_urls):
                    page = await context.new_page()
                    try:
                        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
                        await page.wait_for_timeout(3000)

                        # 展开评论区
                        expand_elem = await self._try_selectors(page, self.EXPAND_COMMENT_SELECTORS)
                        if expand_elem:
                            try:
                                await expand_elem.click()
                                await page.wait_for_timeout(1000)
                            except Exception:
                                pass

                        # 滚动加载更多
                        for _ in range(scroll_count):
                            try:
                                await page.evaluate("window.scrollBy(0, 500)")
                            except Exception:
                                pass
                            await page.wait_for_timeout(800)

                        # 提取评论
                        comments = await self._scrape_comments(page, max_comments_per_video)

                        # 评论总数
                        comment_total = 0
                        try:
                            count_text = await self._get_text(page, self.VIDEO_COMMENT_COUNT_SELECTORS)
                            comment_total = parse_count(count_text)
                        except Exception:
                            pass

                        result = {
                            "video_url": url,
                            "comments": [c.model_dump() for c in comments],
                            "comment_count_total": comment_total,
                            "topic_summary": "",
                        }
                        results.append(result)
                        print(f"[{i+1}/{total}] 评论抓取完成: {len(comments)} 条", flush=True)

                    except Exception as e:
                        results.append({
                            "video_url": url,
                            "comments": [],
                            "comment_count_total": 0,
                            "topic_summary": "（评论抓取失败）",
                        })
                        print(f"[{i+1}/{total}] 评论抓取失败: {str(e)}", flush=True)
                    finally:
                        await page.close()

                    # 反爬延迟
                    await random_delay(2, 4)
            finally:
                await context.close()
                await browser.close()

        return results

    # ========== 单个视频抓取（完整） ==========

    async def scrape_video(self, url: str) -> Dict[str, Any]:
        """抓取单个视频的完整数据"""
        if not self.cookie_manager.has_cookie():
            return {"error": "COOKIE_NOT_FOUND", "message": "请先运行 `python cli/main.py auth` 扫码登录"}

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await self._create_context(browser)

            try:
                for attempt in range(2):
                    try:
                        video = await self._scrape_video_detail(context, url)

                        # 博主名称和 ID
                        blogger_name = ""
                        blogger_id = ""
                        try:
                            user_link = await page.query_selector("a[href*='/user/']")
                            if user_link:
                                href = await user_link.get_attribute("href") or ""
                                if "/user/" in href:
                                    blogger_id = href.split("/user/")[-1].split("?")[0]
                        except Exception:
                            pass

                        result = {
                            "title": video.title,
                            "desc": video.desc,
                            "like_count": video.like_count,
                            "play_count": video.play_count,
                            "comment_count": video.comment_count,
                            "collect_count": video.collect_count,
                            "share_count": video.share_count,
                            "publish_time": video.publish_time,
                            "duration": video.duration,
                            "tags": video.tags,
                            "blogger_name": blogger_name,
                            "blogger_id": blogger_id,
                            "top_comments": [c.model_dump() for c in video.top_comments],
                        }
                        return result

                    except Exception as e:
                        if attempt == 1:
                            return {"error": "SCRAPE_ERROR", "message": f"抓取失败: {str(e)}"}
                        await random_delay(2, 4)
            finally:
                await context.close()
                await browser.close()
