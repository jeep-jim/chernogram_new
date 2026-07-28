from pathlib import Path

path = Path('lib/music_player.dart')
text = path.read_text(encoding='utf-8')
old = """            addedAt: DateTime.fromMillisecondsSinceEpoch(asset.createDateSecond * 1000)
                .toUtc(),"""
new = """            addedAt: asset.createDateSecond == null
                ? DateTime.now().toUtc()
                : DateTime.fromMillisecondsSinceEpoch(
                    asset.createDateSecond! * 1000,
                  ).toUtc(),"""
if old not in text:
    raise SystemExit('music_player.dart: nullable createDateSecond block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Fixed nullable AssetEntity.createDateSecond')
