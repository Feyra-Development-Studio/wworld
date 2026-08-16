package ru.wworld;

import android.app.Activity;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;

/**
 * Деятельность, в которой живёт терминал.
 *
 * Она делает ровно три вещи и не делает больше ничего: отдаёт поверхность,
 * передаёт ввод и говорит, где лежат ресурсы. Ни отрисовки, ни разбора
 * событий здесь нет — всё это умеет BearLibTerminal, и дублировать его на
 * Java значило бы обходить движок вместо того, чтобы им пользоваться.
 */
public class TerminalActivity extends Activity implements SurfaceHolder.Callback {

    static {
        // Порядок важен: библиотека терминала должна быть загружена раньше
        // связки, которая на неё ссылается.
        System.loadLibrary("BearLibTerminal");
        System.loadLibrary("wworld");
    }

    private native void nativeStart(Object assetManager, int touchSlop, String dataDir);
    private native boolean nativeIsThreaded();
    private native void nativeStep();
    private native void nativeStop();
    private native void nativeSurfaceChanged(Object surface);
    private native void nativePointer(int action, int x, int y, int isTouch);
    private native void nativeKey(int keyCode, int pressed, int unicode);

    private SurfaceView surfaceView;

    /* Запасной ход на случай, когда своего потока терминалу не досталось.
     *
     * Тогда цикл гонит сама система: сюда приходит по кадру каждые полсотни
     * миллисекунд. Это медленнее и грубее, но игра остаётся играбельной, а
     * приложение — живым: занимать поток деятельности бесконечным циклом
     * нельзя, система убьёт его за неотзывчивость. */
    private Handler stepHandler;
    private final Runnable stepRunnable = new Runnable() {
        @Override public void run() {
            nativeStep();
            stepHandler.postDelayed(this, 50);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        // Экран не гасим: игра пошаговая, между ходами игрок думает, и
        // погасший на середине хода экран — это потерянный ход.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        surfaceView = new SurfaceView(this);
        surfaceView.getHolder().addCallback(this);
        surfaceView.setFocusable(true);
        surfaceView.setFocusableInTouchMode(true);

        // Касания снимаются с самой поверхности, а не с деятельности: у
        // деятельности координаты считаются от окна, и любая полоса сверху
        // сдвигала бы клетку по вертикали — игрок тыкал бы в одно, а попадал
        // в другое.
        surfaceView.setOnTouchListener(new View.OnTouchListener() {
            @Override public boolean onTouch(View view, MotionEvent event) {
                return handlePointer(event);
            }
        });
        surfaceView.setOnGenericMotionListener(new View.OnGenericMotionListener() {
            @Override public boolean onGenericMotion(View view, MotionEvent event) {
                return handlePointer(event);
            }
        });

        setContentView(surfaceView);

        // Порог, дальше которого движение пальца перестаёт быть щелчком.
        // Библиотека о плотности точек экрана не знает, а здесь она известна.
        int touchSlop = ViewConfiguration.get(this).getScaledTouchSlop();
        nativeStart(getAssets(), touchSlop, unpackData());

        if (!nativeIsThreaded()) {
            stepHandler = new Handler(Looper.getMainLooper());
            stepHandler.post(stepRunnable);
        }
    }

    @Override
    protected void onDestroy() {
        if (stepHandler != null)
            stepHandler.removeCallbacks(stepRunnable);
        nativeStop();
        super.onDestroy();
    }

    /**
     * Раскладывает карту из ресурсов APK в хранилище приложения.
     *
     * Ресурсы в APK — не файлы: у них нет пути, и обычным файловым чтением их
     * не открыть. Библиотека умеет читать их через AAssetManager, но игра на
     * Pascal читает файлы, и переучивать её ради одной платформы значило бы
     * тащить Android внутрь общего кода.
     *
     * Поэтому раскладываем один раз при запуске. Возвращается путь, по
     * которому игра найдёт выгрузку.
     */
    private String unpackData() {
        File target = new File(getFilesDir(), "csv");
        AssetManager assets = getAssets();
        try {
            String[] names = assets.list("csv");
            if (names == null || names.length == 0)
                return target.getAbsolutePath();

            target.mkdirs();
            for (String name : names) {
                File out = new File(target, name);
                // Раскладываем только недостающее: при каждом запуске
                // переписывать десятки файлов незачем.
                if (out.exists() && out.length() > 0)
                    continue;
                try (InputStream in = assets.open("csv/" + name);
                     OutputStream os = new FileOutputStream(out)) {
                    byte[] buffer = new byte[16384];
                    int read;
                    while ((read = in.read(buffer)) > 0)
                        os.write(buffer, 0, read);
                }
            }
        } catch (IOException e) {
            // Не падаем: без карты приложение всё равно должно запуститься и
            // сказать, что случилось, а не исчезнуть с экрана.
            Log.e("wworld", "карта не разложилась: " + e.getMessage());
        }
        return target.getAbsolutePath();
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        nativeSurfaceChanged(holder.getSurface());
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        nativeSurfaceChanged(holder.getSurface());
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        // Не ошибка, а обычное сворачивание: поверхность отобрали вместе с
        // контекстом, и рисовать до следующего surfaceCreated некуда.
        nativeSurfaceChanged(null);
    }

    private boolean handlePointer(MotionEvent event) {
        // Палец и мышь различаются только здесь и только ради того, когда
        // посылать нажатие: у мыши сразу, у пальца при отрыве. Наружу события
        // одни и те же.
        int isTouch = (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE? 0: 1;

        int action;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: action = 0; break;
            case MotionEvent.ACTION_UP: action = 1; break;
            case MotionEvent.ACTION_MOVE: action = 2; break;
            // Движение мыши без нажатой кнопки — тоже движение указателя.
            case MotionEvent.ACTION_HOVER_MOVE: action = 2; break;
            case MotionEvent.ACTION_CANCEL:
                // Жест отменила система — например, вытянули шторку.
                // Для терминала это отпускание вне поля: щелчка быть не должно.
                action = 1;
                break;
            default:
                return true;
        }

        nativePointer(action, (int) event.getX(), (int) event.getY(), isTouch);
        return true;
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        // Кнопку «назад» не перехватываем: выход из игры остаётся за системой.
        if (keyCode == KeyEvent.KEYCODE_BACK)
            return super.onKeyDown(keyCode, event);

        int code = AndroidKeys.toTerminal(keyCode);
        if (code == 0)
            return super.onKeyDown(keyCode, event);

        // Печатный знак разбирает Java: раскладки и составные знаки живут
        // здесь, и повторять эту работу в библиотеке было бы хуже.
        int unicode = event.getUnicodeChar(event.getMetaState());
        nativeKey(code, 1, unicode);
        return true;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK)
            return super.onKeyUp(keyCode, event);

        int code = AndroidKeys.toTerminal(keyCode);
        if (code == 0)
            return super.onKeyUp(keyCode, event);

        nativeKey(code, 0, 0);
        return true;
    }
}
