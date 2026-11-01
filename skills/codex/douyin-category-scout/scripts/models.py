"""数据模型"""
from datetime import datetime
from typing import List
from pydantic import BaseModel, Field


class BloggerItem(BaseModel):
    """搜索结果中的单个博主"""
    blogger_name: str = ""       # 博主名称
    fans_count: str = ""         # 粉丝数（原始文本，如"699.3万"）
    fans_count_int: int = 0      # 解析后的整数（用于排序）
    total_likes: str = ""        # 获赞数（原始文本，如"8503.1万"）
    total_likes_int: int = 0     # 解析后的整数
    profile_url: str = ""        # https://www.douyin.com/user/XXX


class CategoryScoutResult(BaseModel):
    """类目搜索抓取结果"""
    keyword: str = ""            # 搜索关键词
    total_found: int = 0         # 搜索结果去重后总数
    top_100: List[BloggerItem] = Field(default_factory=list)
    scrape_time: str = Field(default_factory=lambda: datetime.now().isoformat())
