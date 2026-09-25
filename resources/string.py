import os
import re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_FILE = os.path.join(BASE_DIR, "strings.lua")
OUTPUT_MD = os.path.join(BASE_DIR, "dst_prefabs_slim.md")

def compress_strings():
    if not os.path.exists(INPUT_FILE):
        print(f"错误：请确保 strings.lua 位于该目录：\n{BASE_DIR}")
        return

    with open(INPUT_FILE, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # 1. 严格使用 \b 单词边界，防止把 SYSTEM_NAMES 误判为 NAMES
    names_match = re.search(r'\bNAMES\s*=\s*\{(.*?)\n\s*\},', content, re.DOTALL)
    if not names_match:
        print("未能在文件中找到 NAMES 表！")
        return

    names_block = names_match.group(1)

    # 2. 逐行匹配 KEY = "Name"
    pattern = re.compile(r'([A-Za-z0-9_]+)\s*=\s*"(.*?)"')
    items = pattern.findall(names_block)

    prefab_dict = {}
    for key, name in items:
        # 跳过占位符、无名项或带格式化花括号的模板条目
        if key in ["DEFAULT", "NONE"] or "{" in name:
            continue
        # 饥荒标准：NAMES 的 KEY 对应的小写即为 Prefab 代码
        prefab_code = key.lower()
        prefab_dict[name] = prefab_code

    # 3. 输出专供 AI 读取的单份极简 Markdown
    with open(OUTPUT_MD, "w", encoding="utf-8") as f:
        f.write("# DST Prefab Quick Reference\n\n")
        for name, code in sorted(prefab_dict.items()):
            f.write(f"- {name}: `{code}`\n")

    print(f"提取成功！")
    print(f"共提取 {len(prefab_dict)} 个游戏实体 Prefab。")
    print(f"文件已保存为: {OUTPUT_MD}")

if __name__ == "__main__":
    compress_strings()