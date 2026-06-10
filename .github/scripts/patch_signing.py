#!/usr/bin/env python3
"""Write complete android/app/build.gradle with signing config and proper SDK/Kotlin versions."""
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
            storeFile file("fntv-release.jks")
            storePassword "fntv2024"
            keyAlias "fntv"
            keyPassword "fntv2024"
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled false
        }
    }
}

flutter {
    source '../..'
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib:1.9.22"
}
'''

def main():
    import subprocess

    # Generate keystore
    subprocess.run([
        'keytool', '-genkeypair', '-v',
        '-keystore', 'android/app/fntv-release.jks',
        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '36500',
        '-alias', 'fntv',
        '-storepass', 'fntv2024',
        '-keypass', 'fntv2024',
        '-dname', 'CN=FNTV, OU=Dev, O=FNTV, L=Jinan, ST=SD, C=CN',
    ], check=True)
    print('Keystore created.')

    path = 'android/app/build.gradle'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(BUILD_GRADLE)
    print(f'Written: {path}')

if __name__ == '__main__':
    main()
