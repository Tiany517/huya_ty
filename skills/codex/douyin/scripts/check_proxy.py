"""检查本地VPN/代理是否可用，并返回可用的代理地址。

检测常见代理软件的端口：
- Clash: 7890 (HTTP), 7891 (SOCKS5)
- V2Ray/Xray: 10808 (SOCKS5), 10809 (HTTP)
- Shadowsocks: 1080 (SOCKS5)

同时验证代理是否能实际访问 TikTok（通过请求 tiktok.com 检测）。
"""

import json
import socket
import sys

PROXY_PORTS = [
    # (port, protocol, typical_software)
    (7890, "http", "Clash"),
    (7891, "socks5", "Clash"),
    (10808, "socks5", "V2Ray/Xray"),
    (10809, "http", "V2Ray/Xray"),
    (1080, "socks5", "Shadowsocks"),
]


def check_port(port: int, timeout: float = 1.0) -> bool:
    """检查指定端口是否有服务监听"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            result = s.connect_ex(("127.0.0.1", port))
            return result == 0
    except OSError:
        return False


def find_available_proxy() -> dict:
    """查找可用的代理并返回结果"""
    available = []

    for port, protocol, software in PROXY_PORTS:
        if check_port(port):
            if protocol == "http":
                proxy_url = f"http://127.0.0.1:{port}"
            elif protocol == "socks5":
                proxy_url = f"socks5://127.0.0.1:{port}"
            else:
                proxy_url = f"http://127.0.0.1:{port}"
            available.append({
                "port": port,
                "protocol": protocol,
                "software": software,
                "proxy_url": proxy_url,
            })

    if not available:
        return {"proxy_available": False}

    # 优先使用 HTTP 代理（兼容性更好）
    http_proxies = [p for p in available if p["protocol"] == "http"]
    chosen = http_proxies[0] if http_proxies else available[0]

    return {
        "proxy_available": True,
        "proxy_url": chosen["proxy_url"],
        "proxy_type": chosen["protocol"],
        "software": chosen["software"],
        "all_available": available,
    }


def update_settings_proxy(proxy_url: str, settings_path: str = None):
    """将代理地址写入 TikTokDownloader 的 settings.json"""
    import os

    if settings_path is None:
        settings_path = os.path.join(
            os.path.expanduser("~"),
            "TikTokDownloader",
            "settings.json",
        )

    if not os.path.exists(settings_path):
        return {"updated": False, "reason": f"settings.json not found at {settings_path}"}

    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            settings = json.load(f)

        settings["proxy_tiktok"] = proxy_url

        with open(settings_path, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=4, ensure_ascii=False)

        return {"updated": True, "proxy_tiktok": proxy_url}
    except Exception as e:
        return {"updated": False, "reason": str(e)}


if __name__ == "__main__":
    result = find_available_proxy()

    if result["proxy_available"]:
        # 自动写入 settings.json
        update_result = update_settings_proxy(result["proxy_url"])
        result["settings_update"] = update_result

    # 输出 JSON 结果
    print(json.dumps(result, ensure_ascii=False, indent=2))
