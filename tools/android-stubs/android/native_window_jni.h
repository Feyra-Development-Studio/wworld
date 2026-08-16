#pragma once
#include <jni.h>
struct ANativeWindow;
inline ANativeWindow* ANativeWindow_fromSurface(JNIEnv*, jobject) { return nullptr; }
inline void ANativeWindow_release(ANativeWindow*) { }
