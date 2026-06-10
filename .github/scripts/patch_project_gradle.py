#!/usr/bin/env python3
"""Write complete android/build.gradle (project-level) with proper Kotlin/AGP versions."""
import os

BUILD_GRADLE = r'''allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = '../build'
subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
}
subprojects {
    project.evaluationDependsOn(':app')
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
'''

SETTINGS_GRADLE = r'''pluginManagement {
    def flutterSdkPath = {
        def properties = new Properties()
        file("local.properties").withInputStream { properties.load(it) }
        def flutterSdkPath = properties.getProperty("flutter.sdk")
        assert flutterSdkPath != null, "flutter.sdk not set in local.properties"
        return flutterSdkPath
    }()

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    id "com.android.application" version "8.1.0" apply false
    id "org.jetbrains.kotlin.android" version "1.9.22" apply false
}

include ":app"
'''

def main():
    # Write project-level build.gradle
    path1 = 'android/build.gradle'
    os.makedirs(os.path.dirname(path1), exist_ok=True)
    with open(path1, 'w') as f:
        f.write(BUILD_GRADLE)
    print(f'Written: {path1}')

    # Write settings.gradle with Kotlin plugin version
    path2 = 'android/settings.gradle'
    with open(path2, 'w') as f:
        f.write(SETTINGS_GRADLE)
    print(f'Written: {path2}')

if __name__ == '__main__':
    main()
