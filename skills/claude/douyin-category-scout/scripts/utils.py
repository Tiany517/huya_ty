"""通用工具函数"""
import asyncio
import random
import re
from typing import Optional


async def random_delay(min_seconds: float = 1.0, max_seconds: float = 3.0) -> None:
    """随机延迟，用于反爬（异步版，不阻塞事件循环）"""
    delay = random.uniform(min_seconds, max_seconds)
    await asyncio.sleep(delay)


def parse_count(text: str) -> int:
    """解析抖音数字格式（支持 w/万/亿 后缀）

    Examples:
        "699.3万" -> 6993000
        "1.2亿"  -> 120000000
        "8503.1万" -> 85031000
        "100"     -> 100
    """
    if not text:
        return 0
    text = text.strip()
    if "亿" in text:
        num = re.sub(r"[^\d.]", "", text)
        return int(float(num) * 100000000) if num else 0
    if "w" in text.lower() or "万" in text:
        num = re.sub(r"[^\d.]", "", text)
        return int(float(num) * 10000) if num else 0
    num = re.sub(r"[^\d]", "", text)
    return int(num) if num else 0


def extract_sec_user_id(url: str) -> Optional[str]:
    """从抖音用户主页链接提取 sec_user_id

    Examples:
        "https://www.douyin.com/user/MS4wLjABAAAA" -> "MS4wLjABAAAA"
    """
    match = re.search(r"/user/([^/?#]+)", url)
    if match:
        return match.group(1)
    return None
