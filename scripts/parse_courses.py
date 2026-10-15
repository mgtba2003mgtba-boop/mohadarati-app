import json
import re
import html

filepath = r"C:\Users\Almustaqbal\.gemini\antigravity\brain\bfc00863-723c-4025-b49e-8dd823d96abb\.system_generated\steps\10055\content.md"

with open(filepath, "r", encoding="utf-8") as f:
    text = f.read()

m = re.search(r'data-page="([^"]+)"', text)
if not m:
    m = re.search(r'data-page=\'([^\']+)\'', text)

if m:
    raw_json = html.unescape(m.group(1))
    data = json.loads(raw_json)
    props = data.get("props", {})
    print("Props keys:", list(props.keys()))
    for k in props:
        print(f"Key: {k} -> {type(props[k])}")
        if isinstance(props[k], dict):
            print(f"   Subkeys of {k}:", list(props[k].keys())[:10])
        elif isinstance(props[k], list) and len(props[k]) > 0:
            print(f"   Sample item of {k}:", props[k][0] if not isinstance(props[k][0], dict) else list(props[k][0].keys()))

    with open("scratch_courses_props.json", "w", encoding="utf-8") as out:
        json.dump(props, out, ensure_ascii=False, indent=2)
    print("Saved props to scratch_courses_props.json")
else:
    print("data-page not found in text")
