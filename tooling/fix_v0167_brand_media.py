from pathlib import Path
import base64
import zlib

parts = (
    'v0167_c01.txt',
    'v0167_c02.txt',
    'v0167_c03.txt',
    'v0167_c04_05.txt',
    'v0167_c06_07.txt',
    'v0167_c08_09.txt',
    'v0167_c10_11.txt',
    'v0167_c12_13.txt',
    'v0167_c14.txt',
)
payload = ''.join(
    Path('tooling', name).read_text(encoding='utf-8').strip()
    for name in parts
)
source = zlib.decompress(base64.b64decode(payload)).decode('utf-8')
exec(compile(source, 'fix_v0167_brand_media.py', 'exec'))
