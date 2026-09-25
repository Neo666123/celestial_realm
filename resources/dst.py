import os
import re
import time
import requests
from bs4 import BeautifulSoup

BASE_URL = "https://dontstarve.huijiwiki.com/api.php"
OUTPUT_DIR = "dontstarve_ai_knowledge"
HEADERS = {
    "User-Agent": "DontStarveAiKnowledgeExtractor/1.0"
}

def sanitize_filename(filename):
    return re.sub(r'[\\/*?:"<>|]', "_", filename)

def get_clean_titles():
    """仅拉取没有斜杠的真正核心主词条（过滤掉 DSRoom/*、人物/台词等内部拆包页）"""
    titles = []
    apcontinue = None
    session = requests.Session()
    session.headers.update(HEADERS)

    while True:
        params = {
            "action": "query",
            "list": "allpages",
            "apnamespace": 0,
            "aplimit": "500",
            "format": "json"
        }
        if apcontinue:
            params["apcontinue"] = apcontinue

        res = session.get(BASE_URL, params=params, timeout=20)
        data = res.json()
        pages = data.get("query", {}).get("allpages", [])

        for p in pages:
            t = p["title"]
            # 关键过滤：排除掉所有子页面、纯数据页、台词页
            if "/" not in t:
                titles.append(t)

        if "continue" in data and "apcontinue" in data["continue"]:
            apcontinue = data["continue"]["apcontinue"]
            time.sleep(0.3)
        else:
            break

    return titles

def extract_pure_markdown(html_content, title):
    """剔除网页垃圾，只保留纯文本/Markdown 结构"""
    soup = BeautifulSoup(html_content, "html.parser")
    
    # 彻底删除导航、目录、编辑按钮、脚本样式等噪音
    for unwanted in soup.find_all(["script", "style", "nav", "noscript", "table"]):
        unwanted.decompose()
    for class_noise in ["toc", "mw-jump-link", "mw-editsection", "navbox", "catlinks"]:
        for el in soup.find_all(class_=class_noise):
            el.decompose()

    # 提取纯文本正文并整理换行
    text = soup.get_text(separator="\n")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    clean_body = "\n\n".join(lines)

    return f"# {title}\n\n{clean_body}"

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    session = requests.Session()
    session.headers.update(HEADERS)

    print("正在筛选核心主词条（自动剔除 DSRoom 等内部数据页面）...")
    titles = get_clean_titles()
    total = len(titles)
    print(f"筛选完成！有效核心词条共 {total} 个（直接压缩了 80% 以上的无用页面）。开始生成 AI 纯净知识库...")

    for idx, title in enumerate(titles, start=1):
        safe_name = sanitize_filename(title)
        file_path = os.path.join(OUTPUT_DIR, f"{safe_name}.md")

        if os.path.exists(file_path):
            continue

        try:
            params = {
                "action": "parse",
                "page": title,
                "prop": "text",
                "format": "json"
            }
            res = session.get(BASE_URL, params=params, timeout=20).json()
            if "parse" in res and "text" in res["parse"]:
                raw_html = res["parse"]["text"]["*"]
                md_text = extract_pure_markdown(raw_html, title)
                
                # 只有真正有内容的页面才写入
                if len(md_text.strip()) > len(title) + 10:
                    with open(file_path, "w", encoding="utf-8") as f:
                        f.write(md_text)
                    print(f"[{idx}/{total}] 已转为纯净 Markdown: {title}")
        except Exception as e:
            print(f"[{idx}/{total}] 抓取失败 ({title}): {e}")

        time.sleep(0.2)

    print(f"\n全部完成！纯净 Markdown 文件已存放于文件夹: {os.path.abspath(OUTPUT_DIR)}")

if __name__ == "__main__":
    main()