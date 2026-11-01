import pytest
from cli.models import Comment, Video, BloggerResult, VideoResult, CliError


class TestComment:
    def test_comment_creation(self):
        c = Comment(user="用户A", text="评论内容", likes=1200)
        assert c.user == "用户A"
        assert c.text == "评论内容"
        assert c.likes == 1200

    def test_comment_defaults(self):
        c = Comment(user="用户B", text="test")
        assert c.likes == 0


class TestVideo:
    def test_video_creation(self):
        v = Video(
            rank=1,
            title="视频标题",
            desc="视频描述",
            url="https://www.douyin.com/video/123",
            like_count=1000,
            play_count=5000,
            comment_count=100,
            publish_time="2024-06-15",
            top_comments=[Comment(user="A", text="nice", likes=10)]
        )
        assert v.rank == 1
        assert v.like_count == 1000
        assert len(v.top_comments) == 1


class TestBloggerResult:
    def test_blogger_result_creation(self):
        result = BloggerResult(
            blogger_name="测试博主",
            blogger_id="MS4wLjABAAAA",
            total_videos=100,
            top_videos=[Video(rank=1, title="t", desc="d", url="https://x", like_count=1, play_count=1, comment_count=1)]
        )
        assert result.blogger_name == "测试博主"
        assert len(result.top_videos) == 1

    def test_blogger_result_json(self):
        result = BloggerResult(
            blogger_name="测试博主",
            blogger_id="id",
            total_videos=10,
            top_videos=[]
        )
        data = result.model_dump()
        assert data["blogger_name"] == "测试博主"
        assert "scrape_time" in data


class TestVideoResult:
    def test_video_result_creation(self):
        result = VideoResult(
            title="标题",
            desc="描述",
            like_count=100,
            play_count=500,
            comment_count=10,
            blogger_name="博主",
            blogger_id="id"
        )
        assert result.title == "标题"


class TestCliError:
    def test_error_json(self):
        err = CliError(code="TEST_ERROR", message="测试错误")
        data = err.model_dump()
        assert data["error"] == "TEST_ERROR"
        assert data["message"] == "测试错误"
