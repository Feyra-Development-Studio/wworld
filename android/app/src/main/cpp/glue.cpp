/*
 * Связка между деятельностью приложения и BearLibTerminal.
 *
 * Здесь нет ни игры, ни отрисовки — только передача поверхности, ввода и
 * ресурсов из Java в библиотеку. Игра появится следующим шагом; сейчас задача
 * доказать, что порт живой: терминал открывается на устройстве, получает
 * контекст GLES3 и рисует.
 *
 * Терминал работает в своём потоке. Поток деятельности приложения занимать
 * нельзя: система убьёт приложение, если он перестанет отвечать, а игровой
 * цикл именно этим и занимается.
 */

#include <BearLibTerminal.h>

#include <android/asset_manager_jni.h>
#include <android/log.h>
#include <android/native_window_jni.h>
#include <jni.h>

#include <atomic>
#include <thread>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "wworld", __VA_ARGS__)

namespace
{
	std::thread g_thread;
	std::atomic<bool> g_running{false};
	std::atomic<ANativeWindow*> g_pending_surface{nullptr};
	ANativeWindow* g_current_surface = nullptr;
	std::atomic<int> g_touch_slop{0};

	void TerminalThread()
	{
		// Поверхности может ещё не быть: surfaceCreated приходит когда
		// придёт. Ждём её, а не открываем терминал в пустоту.
		while (g_running && g_pending_surface.load() == nullptr)
			std::this_thread::sleep_for(std::chrono::milliseconds(16));

		if (!g_running)
			return;

		if (!terminal_open())
		{
			LOGI("terminal_open не отработал");
			return;
		}

		terminal_log(TK_LOG_INFO, "терминал открыт на устройстве");

		// Порог задаётся только теперь: до открытия терминала окна нет, и
		// передавать значение некуда.
		if (int slop = g_touch_slop.load())
			terminal_android_touch_slop(slop);

		// Размер сетки считается от экрана: на Android окно всегда равно
		// экрану, и просить окно определённого размера бессмысленно.
		int cell_w = terminal_state(TK_CELL_WIDTH);
		int cell_h = terminal_state(TK_CELL_HEIGHT);
		int screen_w = terminal_state(TK_SCREEN_WIDTH);
		int screen_h = terminal_state(TK_SCREEN_HEIGHT);

		char setting[128];
		if (cell_w > 0 && cell_h > 0 && screen_w > 0 && screen_h > 0)
		{
			snprintf(setting, sizeof(setting), "window: size=%dx%d",
				screen_w / cell_w, screen_h / cell_h);
			terminal_set(setting);
		}

		LOGI("экран %dx%d, ячейка %dx%d, сетка %dx%d",
			screen_w, screen_h, cell_w, cell_h,
			terminal_state(TK_WIDTH), terminal_state(TK_HEIGHT));

		while (g_running)
		{
			ANativeWindow* surface = g_pending_surface.load();
			if (surface != g_current_surface)
			{
				terminal_android_surface(surface);
				g_current_surface = surface;
			}

			terminal_clear();
			terminal_color(color_from_name("white"));
			terminal_print(1, 1, "BearLibTerminal на Android");
			terminal_color(color_from_name("orange"));
			terminal_print(1, 3, "########  ......  @");
			terminal_color(color_from_name("cyan"));
			terminal_print(1, 5, "кириллица: этаж 1/10");
			terminal_refresh();

			// Событий ждём с ожиданием, а не крутим цикл впустую: игра
			// пошаговая, и рисовать шестьдесят раз в секунду неподвижную
			// картинку значит зря жечь батарею.
			terminal_delay(50);
		}

		terminal_close();
	}
}

extern "C"
{

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativeStart(JNIEnv* env, jobject, jobject asset_manager, jint touch_slop)
{
	if (g_running.exchange(true))
		return;

	terminal_set_asset_manager(AAssetManager_fromJava(env, asset_manager));
	g_touch_slop.store(touch_slop);
	g_thread = std::thread(TerminalThread);
}

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativeStop(JNIEnv*, jobject)
{
	g_running = false;
	if (g_thread.joinable())
		g_thread.join();

	if (ANativeWindow* surface = g_pending_surface.exchange(nullptr))
		ANativeWindow_release(surface);
}

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativeSurfaceChanged(JNIEnv* env, jobject, jobject surface)
{
	ANativeWindow* window = surface? ANativeWindow_fromSurface(env, surface): nullptr;

	// Прежнюю поверхность отпускаем: её удерживал ANativeWindow_fromSurface.
	if (ANativeWindow* old = g_pending_surface.exchange(window))
		ANativeWindow_release(old);
}

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativePointer(JNIEnv*, jobject, jint action, jint x, jint y, jint is_touch)
{
	terminal_android_pointer(action, x, y, is_touch);
}

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativeKey(JNIEnv*, jobject, jint code, jint pressed, jint unicode)
{
	terminal_android_key(code, pressed, unicode);
}

}
