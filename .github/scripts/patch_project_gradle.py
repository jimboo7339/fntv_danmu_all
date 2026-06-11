#!/usr/bin/env python3
"""Write complete android/build.gradle and settings.gradle with proper Kotlin/AGP versions."""
import os

BUILD_GRADLE = '''allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
    }

    // Force kotlin-stdlib to match the Kotlin plugin version
    configurations.all {
        resolutionStrategy {
            force 'org.jetbrains.kotlin:kotlin-stdlib:2.1.0'
            force 'org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.1.0'
            force 'org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.1.0'
        }
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

SETTINGS_GRADLE = '''pluginManagement {
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
    id "org.jetbrains.kotlin.android" version "2.1.0" apply false
}

include ":app"
'''

GRADLE_WRAPPER = '''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.9-all.zip
'''

def main():
    path1 = 'android/build.gradle'
    os.makedirs(os.path.dirname(path1), exist_ok=True)
    with open(path1, 'w') as f:
        f.write(BUILD_GRADLE)
    print(f'Written: {path1}')

    path2 = 'android/settings.gradle'
    with open(path2, 'w') as f:
        f.write(SETTINGS_GRADLE)
    print(f'Written: {path2}')

    path3 = 'android/gradle/wrapper/gradle-wrapper.properties'
    os.makedirs(os.path.dirname(path3), exist_ok=True)
    with open(path3, 'w') as f:
        f.write(GRADLE_WRAPPER)
    print(f'Written: {path3}')

if __name__ == '__main__':
    main()
