package ru.wworld;

import android.app.Activity;
import android.os.Bundle;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
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

    private native void nativeStart(Object assetManager, int touchSlop);
    private native void nativeStop();
    private native void nativeSurfaceChanged(Object surface);
    private native void nativePointer(int action, int x, int y, int isTouch);
    private native void nativeKey(int keyCode, int pressed, int unicode);

    private SurfaceView surfaceView;

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
        setContentView(surfaceView);

        // Порог, дальше которого движение пальца перестаёт быть щелчком.
        // Библиотека о плотности точек экрана не знает, а здесь она известна.
        int touchSlop = ViewConfiguration.get(this).getScaledTouchSlop();
        nativeStart(getAssets(), touchSlop);
    }

    @Override
    protected void onDestroy() {
        nativeStop();
        super.onDestroy();
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

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        // Палец и мышь различаются только здесь и только ради того, когда
        // посылать нажатие: у мыши сразу, у пальца при отрыве. Наружу события
        // одни и те же.
        int isTouch = (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE? 0: 1;

        int action;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: action = 0; break;
            case MotionEvent.ACTION_UP: action = 1; break;
            case MotionEvent.ACTION_MOVE: action = 2; break;
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
    public boolean onGenericMotionEvent(MotionEvent event) {
        // Движение мыши без нажатой кнопки приходит сюда, а не в onTouchEvent.
        if ((event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE
                && event.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) {
            nativePointer(2, (int) event.getX(), (int) event.getY(), 0);
            return true;
        }
        return super.onGenericMotionEvent(event);
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
