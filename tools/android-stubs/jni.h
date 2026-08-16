/* Заглушки заголовков Android: только чтобы проверить синтаксис связки в
   песочнице, где NDK нет. В сборку не попадают. */
#pragma once
typedef int jint; typedef void* jobject; typedef void* jstring; typedef unsigned char jboolean;
#define JNI_TRUE 1
#define JNI_FALSE 0
#define JNIEXPORT
#define JNICALL
struct JNIEnv { const char* GetStringUTFChars(jstring, void*); void ReleaseStringUTFChars(jstring, const char*); };
