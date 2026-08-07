from pathlib import Path

path = Path('android/app/build.gradle.kts')
text = path.read_text(encoding='utf-8')
old = '''    buildTypes {
        release {
            // APK дополнительно подписывается постоянным ключом в GitHub Actions.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
'''
new = '''    signingConfigs {
        create("chernogramRelease") {
            val keyPath = System.getenv("CG_KEYSTORE_PATH")
            if (!keyPath.isNullOrBlank()) {
                storeFile = file(keyPath)
                storePassword = System.getenv("CG_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CG_KEY_ALIAS")
                keyPassword = System.getenv("CG_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val keyPath = System.getenv("CG_KEYSTORE_PATH")
            signingConfig = if (!keyPath.isNullOrBlank()) {
                signingConfigs.getByName("chernogramRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
'''
if old not in text:
    raise SystemExit('Android signing block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Permanent Chernogram release signing configuration applied')
