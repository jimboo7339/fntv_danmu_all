#!/usr/bin/env python3
"""Write complete android/app/build.gradle with signing config using committed keystore."""
import os

BUILD_GRADLE = r'''def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader ->
        localProperties.load(reader)
    }
}

def flutterRoot = localProperties.getProperty('flutter.sdk')
if (flutterRoot == null) {
    throw new GradleException("Flutter SDK not found. Define location with flutter.sdk in the local.properties file.")
}

def flutterVersionCode = localProperties.getProperty('flutter.versionCode')
if (flutterVersionCode == null) {
    flutterVersionCode = "1"
}

def flutterVersionName = localProperties.getProperty('flutter.versionName')
if (flutterVersionName == null) {
    flutterVersionName = "1.0"
}

apply plugin: 'com.android.application'
apply plugin: 'kotlin-android'
apply from: "$flutterRoot/packages/flutter_tools/gradle/flutter.gradle"

android {
    namespace "com.fntv.fnos_tv_all"
    compileSdk 36
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = '17'
    }

    sourceSets {
        main.java.srcDirs += 'src/main/kotlin'
    }

    defaultConfig {
        applicationId "com.fntv.fnos_tv_all"
        minSdk 21
        targetSdk 35
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
        multiDexEnabled true
    }

    signingConfigs {
        release {
            storeFile file("fntv-release.p12")
            storePassword "fntv2024"
            keyAlias "fntv"
            keyPassword "fntv2024"
            storeType "PKCS12"
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}

flutter {
    source '../..'
}

dependencies {
    implementation "androidx.media3:media3-exoplayer:1.4.1"
    implementation "androidx.media3:media3-exoplayer-hls:1.4.1"
    implementation "androidx.media3:media3-ui:1.4.1"
}
'''

def main():
    path = 'android/app/build.gradle'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(BUILD_GRADLE)
    print(f'Written: {path}')

if __name__ == '__main__':
    main()
