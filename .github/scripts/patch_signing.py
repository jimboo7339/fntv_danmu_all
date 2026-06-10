#!/usr/bin/env python3
"""Patch build.gradle to add release signing config."""
import re

GRADLE_PATH = 'android/app/build.gradle'

def main():
    with open(GRADLE_PATH, 'r') as f:
        content = f.read()

    # Add signingConfigs before buildTypes
    signing_block = '''    signingConfigs {
        release {
            storeFile file("fntv-release.jks")
            storePassword "fntv2024"
            keyAlias "fntv"
            keyPassword "fntv2024"
        }
    }
'''
    # Insert before the first "buildTypes {"
    if 'signingConfigs' not in content:
        content = content.replace('    buildTypes {', signing_block + '    buildTypes {', 1)
        print('  Added signingConfigs block')

    # Add signingConfig to release buildType
    # Match "release {" that's inside buildTypes
    if 'signingConfig signingConfigs.release' not in content:
        # Find the release buildType and add signingConfig
        content = re.sub(
            r'(release\s*\{)',
            r'\1\n                signingConfig signingConfigs.release',
            content,
            count=1
        )
        print('  Added signingConfig to release buildType')

    with open(GRADLE_PATH, 'w') as f:
        f.write(content)

    print(f'  Written: {GRADLE_PATH}')
    print('Done.')

if __name__ == '__main__':
    main()
