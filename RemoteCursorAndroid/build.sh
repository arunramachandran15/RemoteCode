#!/bin/bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk.jdk/Contents/Home
export PATH=$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH

cd "$(dirname "$0")"
chmod +x gradlew

echo "Building Remote Cursor Android..."
echo "ANDROID_HOME=$ANDROID_HOME"
echo "JAVA_HOME=$JAVA_HOME"

./gradlew assembleDebug --stacktrace

if [ $? -eq 0 ]; then
    APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
    echo ""
    echo "Build successful! APK at: $APK_PATH"
    echo ""
    
    if command -v adb &> /dev/null || [ -f "$ANDROID_HOME/platform-tools/adb" ]; then
        ADB=${ANDROID_HOME}/platform-tools/adb
        DEVICES=$($ADB devices | grep -v "List" | grep "device" | wc -l | tr -d ' ')
        if [ "$DEVICES" -gt "0" ]; then
            echo "Installing on connected device..."
            $ADB install -r "$APK_PATH"
        else
            echo "No Android device connected. Connect a device and run:"
            echo "  $ADB install -r $APK_PATH"
        fi
    fi
else
    echo "Build failed!"
    exit 1
fi
