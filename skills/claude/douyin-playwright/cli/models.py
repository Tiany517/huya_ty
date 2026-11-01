from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field


class Comment(BaseModel):
    """评论模型"""
    user: str
    text: str
    likes: int = 0


class Video(BaseModel):
    """视频模型 — 包含详情页全部字段"""
    rank: int = 0
    title: str = ""
    desc: str = ""
    url: str = ""
    like_count: int = 0
    play_count: int = 0
    comment_count: int = 0
    collect_count: int = 0      # 收藏数（需详情页获取）
    share_count: int = 0        # 转发数（需详情页获取）
    publish_time: str = ""      # 发布日期（需详情页获取）
    duration: str = ""          # 视频时长
    tags: str = ""              # 标签（如 #财经 #科普）
    comment_topic: str = ""     # 评论区话题摘要（由 Step 4.5 subagent 填充）
    top_comments: List[Comment] = Field(default_factory=list)
    video_id: str = ""          # 视频ID（从URL提取）


class BloggerProfile(BaseModel):
    """博主个人信息 — Sheet 1 需要"""
    blogger_name: str = ""
    douyin_id: str = ""         # 抖音号
    fans_count: str = ""        # 粉丝数
    total_likes: str = ""       # 获赞数
    total_videos: str = ""      # 作品数
    certification: str = ""     # 认证信息
    description: str = ""       # 简介
    ip_location: str = ""       # IP属地
    sec_user_id: str = ""       # sec_user_id
    profile_url: str = ""       # 主页链接


class BloggerResult(BaseModel):
    """博主抓取结果"""
    blogger_name: str = ""
    blogger_id: str = ""
    profile: BloggerProfile = Field(default_factory=BloggerProfile)
    total_videos: int = 0
    scrape_time: str = Field(default_factory=lambda: datetime.now().isoformat())
    top_videos: List[Video] = Field(default_factory=list)


class VideoResult(BaseModel):
    """单个视频抓取结果"""
    title: str = ""
    desc: str = ""
    like_count: int = 0
    play_count: int = 0
    comment_count: int = 0
    collect_count: int = 0
    share_count: int = 0
    publish_time: str = ""
    duration: str = ""
    tags: str = ""
    comment_topic: str = ""
    blogger_name: str = ""
    blogger_id: str = ""
    top_comments: List[Comment] = Field(default_factory=list)


class CommentResult(BaseModel):
    """评论区抓取结果（v2 输出）"""
    video_url: str = ""
    comments: List[Comment] = Field(default_factory=list)
    comment_count_total: int = 0
    topic_summary: str = ""     # 由 Step 4.5 subagent 填充


class CliError(BaseModel):
    """CLI 错误输出模型"""
    error: str = Field(alias="code")
    message: str

    model_config = {"populate_by_name": True}

    def model_dump(self, **kwargs):
        return {"error": self.error, "message": self.message}
