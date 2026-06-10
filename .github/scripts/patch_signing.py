#!/usr/bin/env python3
"""Patch build.gradle to add release signing config."""
import re

GRADLE_PATH = 'android/app/build.gradle'

def main():
    with open(GRADLE_PATH, 'r') as f:
        content = f.read()

    # Step 1: Add signingConfigs block BEFORE "buildTypes {"
    signing_block = '''    signingConfigs {
        release {
            storeFile file("fntv-release.jks")
            storePassword "fntv2024"
            keyAlias "fntv"
            keyPassword "fntv2024"
        }
    }
'''
    if 'signingConfigs' not in content:
        content = content.replace('    buildTypes {', signing_block + '    buildTypes {', 1)
        print('  Added signingConfigs block')

    # Step 2: Add "signingConfig signingConfigs.release" inside buildTypes > release
    # Match "buildTypes {" then find the first "release {" inside it
    if 'signingConfig signingConfigs.release' not in content:
        # Find "buildTypes {" and insert signingConfig after the next "release {"
        bt_match = re.search(r'buildTypes\s*\{', content)
        if bt_match:
            # Find the first "release {" AFTER "buildTypes {"
            after_bt = content[bt_match.end():]
            release_match = re.search(r'release\s*\{', after_bt)
            if release_match:
                insert_pos = bt_match.end() + release_match.end()
                content = (
                    content[:insert_pos] +
                    '\n                signingConfig signingConfigs.release' +
                    content[insert_pos:]
                )
                print('  Added signingConfig to buildTypes.release')

    with open(GRADLE_PATH, 'w') as f:
        f.write(content)

    print(f'  Written: {GRADLE_PATH}')
    print('Done.')

if __name__ == '__main__':
    main()
