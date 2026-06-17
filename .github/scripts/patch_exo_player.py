#!/usr/bin/env python3
"""Copy ExoPlayer Kotlin sources and patch Android build for CI."""
import os
import shutil

OVERLAY = '.github/android_overlay/exo'
KOTLIN_PKG = 'android/app/src/main/kotlin/com/fntv/fnos_tv_all'

MAIN_ACTIVITY = '''package com.fntv.fnos_tv_all

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ExoPlayerPlugin())
    }
}
'''


def main():
    print('Patching ExoPlayer Android integration...')
    os.makedirs(KOTLIN_PKG, exist_ok=True)
    for name in os.listdir(OVERLAY):
        src = os.path.join(OVERLAY, name)
        if os.path.isfile(src) and name.endswith('.kt'):
            shutil.copy2(src, os.path.join(KOTLIN_PKG, name))
            print(f'  Copied: {name}')

    gradle_path = 'android/app/build.gradle'
    with open(gradle_path, 'r', encoding='utf-8') as f:
        content = f.read()
    if 'media3-exoplayer' not in content:
        content = content.rstrip() + '''

dependencies {
    implementation "androidx.media3:media3-exoplayer:1.4.1"
    implementation "androidx.media3:media3-exoplayer-hls:1.4.1"
    implementation "androidx.media3:media3-ui:1.4.1"
}
'''
        with open(gradle_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print('  Patched: android/app/build.gradle')

    with open(os.path.join(KOTLIN_PKG, 'MainActivity.kt'), 'w', encoding='utf-8') as f:
        f.write(MAIN_ACTIVITY)
    print('  Written: MainActivity.kt')
    print('Done.')


if __name__ == '__main__':
    main()
