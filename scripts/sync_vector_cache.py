import os
import shutil
import json

src = 'C:/Users/Almustaqbal/Downloads/nnnnnnn/vector_cache.json'
with open(src, encoding='utf-8') as f:
    d = json.load(f)
count = len(d.get('students', []))
print(f"Source {src} has {count} students.")

targets = [
    'C:/Users/Almustaqbal/Downloads/nnnnnnn_repo/vector_cache.json',
    os.path.join(os.environ['APPDATA'], 'Mujtaba AH', 'vector_cache.json'),
    os.path.join(os.environ['APPDATA'], 'mujtaba-ah', 'vector_cache.json'),
    os.path.join(os.environ['APPDATA'], 'alwah-attendance', 'vector_cache.json')
]

for t in targets:
    os.makedirs(os.path.dirname(t), exist_ok=True)
    shutil.copy2(src, t)
    print(f"Successfully copied to: {t}")
