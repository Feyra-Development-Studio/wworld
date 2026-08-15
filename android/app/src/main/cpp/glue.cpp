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
#include <chrono>
#include <stdexcept>
#include <system_error>
#include <thread>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "wworld", __VA_ARGS__)

namespace
{
	std::thread g_thread;
	std::atomic<bool> g_running{false};
	std::atomic<ANativeWindow*> g_pending_surface{nullptr};
	ANativeWindow* g_current_surface = nullptr;
	std::atomic<int> g_touch_slop{0};
	std::atomic<bool> g_threaded{false};
	bool g_grid_fitted = false;

	std::atomic<bool> g_opened{false};

	// Открытие терминала. Отделено от цикла нарочно: гнать цикл может как
	// свой поток, так и сама система, если потока не досталось.
	bool TerminalOpen()
	{
		if (g_opened)
			return true;

		// Поверхности может ещё не быть: surfaceCreated приходит когда
		// придёт. Открывать терминал в пустоту незачем.
		if (g_pending_surface.load() == nullptr)
			return false;

		if (!terminal_open())
		{
			LOGI("terminal_open не отработал");
			return false;
		}
		g_opened = true;

		// Уровень журнала — до первой записи. По умолчанию он error, и
		// сообщение уровня info просто не дойдёт: ровно это и случилось на
		// прогоне, где терминал открылся, а строки в logcat не было.
		terminal_set("log: level=info");
		terminal_log(TK_LOG_INFO, "терминал открыт на устройстве");

		// Порог задаётся только теперь: до открытия терминала окна нет, и
		// передавать значение некуда.
		if (int slop = g_touch_slop.load())
			terminal_android_touch_slop(slop);

		return true;
	}

	// Один шаг: подхватить поверхность, если она сменилась, и нарисовать кадр.
	void TerminalStep()
	{
		if (!g_opened && !TerminalOpen())
			return;

		ANativeWindow* surface = g_pending_surface.load();
		if (surface != g_current_surface)
		{
			terminal_android_surface(surface);
			g_current_surface = surface;
			g_grid_fitted = false;
		}

		/* Сетка считается от экрана и только после того, как поверхность
		   появилась.
		
		   При открытии терминала её ещё нет: eglQuerySurface спрашивать не у
		   чего, и размер экрана выходит нулевым — что и случилось на первом
		   прогоне, в журнале осталось «экран 0x0». Сетка тогда молча остаётся
		   стандартной 80x25, то есть не по экрану. */
		if (!g_grid_fitted && surface != nullptr)
		{
			int cell_w = terminal_state(TK_CELL_WIDTH);
			int cell_h = terminal_state(TK_CELL_HEIGHT);
			int screen_w = terminal_state(TK_SCREEN_WIDTH);
			int screen_h = terminal_state(TK_SCREEN_HEIGHT);

			if (cell_w > 0 && cell_h > 0 && screen_w > 0 && screen_h > 0)
			{
				char setting[128];
				snprintf(setting, sizeof(setting), "window: size=%dx%d",
					screen_w / cell_w, screen_h / cell_h);
				terminal_set(setting);
				g_grid_fitted = true;

				LOGI("экран %dx%d, ячейка %dx%d, сетка %dx%d",
					screen_w, screen_h, cell_w, cell_h,
					terminal_state(TK_WIDTH), terminal_state(TK_HEIGHT));
			}
		}

		{
			terminal_clear();
			terminal_color(color_from_name("white"));
			terminal_print(1, 1, "BearLibTerminal на Android");
			terminal_color(color_from_name("orange"));
			terminal_print(1, 3, "########  ......  @");
			terminal_color(color_from_name("cyan"));
			terminal_print(1, 5, "кириллица: этаж 1/10");
			terminal_refresh();
		}
	}

	void TerminalThread()
	{
		while (g_running)
		{
			TerminalStep();

			// Ждём, а не крутим цикл впустую: игра пошаговая, и рисовать
			// шестьдесят раз в секунду неподвижную картинку значит зря жечь
			// батарею.
			std::this_thread::sleep_for(std::chrono::milliseconds(50));
		}

		if (g_opened)
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

	/* Свой поток — предпочтительный путь, но не обязательный.
	 *
	 * Занимать поток деятельности приложения нельзя: система убьёт
	 * приложение, если он перестанет отвечать, а игровой цикл именно этим и
	 * занят. Поэтому цикл уходит в отдельный поток.
	 *
	 * Но создание потока может и не удаться — на исчерпании памяти, при
	 * жёстких ограничениях на процесс, на урезанных сборках системы. Тогда
	 * цикл гонит сама система: Java зовёт nativeStep по таймеру, а шаг для
	 * того и отделён от цикла.
	 *
	 * Число ядер тут ни при чём, и по нему решать нельзя: на одном ядре
	 * потоки работают точно так же, просто по очереди. Доступность
	 * проверяется единственным честным способом — попыткой. */
	unsigned cores = std::thread::hardware_concurrency();
	LOGI("ядер видно: %u (0 означает «неизвестно»)", cores);

	try
	{
		g_thread = std::thread(TerminalThread);
		g_threaded = true;
		LOGI("цикл идёт в своём потоке");
	}
	catch (const std::system_error& e)
	{
		g_threaded = false;
		LOGI("поток создать не удалось (%s), цикл будет гнать система", e.what());
	}
}

JNIEXPORT jboolean JNICALL
Java_ru_wworld_TerminalActivity_nativeIsThreaded(JNIEnv*, jobject)
{
	return g_threaded? JNI_TRUE: JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativeStep(JNIEnv*, jobject)
{
	// Зовётся из потока деятельности, только когда своего потока не досталось.
	if (!g_threaded && g_running)
		TerminalStep();
}

JNIEXPORT void JNICALL
Java_ru_wworld_TerminalActivity_nativeStop(JNIEnv*, jobject)
{
	g_running = false;
	if (g_thread.joinable())
		g_thread.join();
	else if (g_opened)
		terminal_close();   // цикл гнала система, закрывать некому

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
