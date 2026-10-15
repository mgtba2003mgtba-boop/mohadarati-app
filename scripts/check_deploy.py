import json

with open(r'C:\Users\Almustaqbal\.gemini\antigravity\brain\bfc00863-723c-4025-b49e-8dd823d96abb\.system_generated\logs\transcript.jsonl', 'r', encoding='utf-8') as f:
    for idx, line in enumerate(f):
        if 4600 <= idx <= 4800:
            obj = json.loads(line)
            calls = obj.get('tool_calls') or []
            for c in calls:
                args = c.get('args', {})
                cmd = args.get('CommandLine') or ''
                if 'git' in cmd or 'clone' in cmd or 'init' in cmd:
                    print(f"Index {idx}: Cwd={args.get('Cwd')} | Cmd={cmd}")
