package ru.wworld;

import android.util.SparseIntArray;
import android.view.KeyEvent;

/**
 * Перевод кодов клавиш Android в коды BearLibTerminal.
 *
 * Живёт на Java нарочно. Раскладки, составные знаки и предсказание ввода —
 * дело системы, и библиотека о них знать не должна; ей достаточно получить
 * тот же `TK_*`, что приходит на Linux и Windows, чтобы игра разбирала
 * клавиши одним и тем же кодом на всех платформах.
 *
 * Клавиатура на Android — не редкость: гибридные смартфоны с выдвижной
 * клавиатурой, кнопочные телефоны, внешняя клавиатура к планшету. Но и не
 * обязанность: игра управляема касанием без единой клавиши.
 */
final class AndroidKeys {

    private static final SparseIntArray MAP = new SparseIntArray();

    private static void put(int androidCode, int terminalCode) {
        MAP.put(androidCode, terminalCode);
    }

    static {
        // Буквы: TK_A..TK_Z идут подряд от 0x04, как и KEYCODE_A..KEYCODE_Z.
        for (int i = 0; i < 26; i++)
            put(KeyEvent.KEYCODE_A + i, 0x04 + i);

        // Цифры: TK_1..TK_9 подряд от 0x1E, ноль стоит после девятки.
        for (int i = 0; i < 9; i++)
            put(KeyEvent.KEYCODE_1 + i, 0x1E + i);
        put(KeyEvent.KEYCODE_0, 0x27);          // TK_0

        put(KeyEvent.KEYCODE_ENTER, 0x28);      // TK_RETURN
        put(KeyEvent.KEYCODE_ESCAPE, 0x29);     // TK_ESCAPE
        put(KeyEvent.KEYCODE_DEL, 0x2A);        // TK_BACKSPACE
        put(KeyEvent.KEYCODE_TAB, 0x2B);        // TK_TAB
        put(KeyEvent.KEYCODE_SPACE, 0x2C);      // TK_SPACE
        put(KeyEvent.KEYCODE_MINUS, 0x2D);      // TK_MINUS
        put(KeyEvent.KEYCODE_EQUALS, 0x2E);     // TK_EQUALS
        put(KeyEvent.KEYCODE_LEFT_BRACKET, 0x2F);
        put(KeyEvent.KEYCODE_RIGHT_BRACKET, 0x30);
        put(KeyEvent.KEYCODE_BACKSLASH, 0x31);
        put(KeyEvent.KEYCODE_SEMICOLON, 0x33);
        put(KeyEvent.KEYCODE_APOSTROPHE, 0x34);
        put(KeyEvent.KEYCODE_GRAVE, 0x35);
        put(KeyEvent.KEYCODE_COMMA, 0x36);      // TK_COMMA — лестница вверх
        put(KeyEvent.KEYCODE_PERIOD, 0x37);     // TK_PERIOD — лестница вниз
        put(KeyEvent.KEYCODE_SLASH, 0x38);

        // Стрелки — второй способ ходить, наравне с WASD.
        put(KeyEvent.KEYCODE_DPAD_RIGHT, 0x4F); // TK_RIGHT
        put(KeyEvent.KEYCODE_DPAD_LEFT, 0x50);  // TK_LEFT
        put(KeyEvent.KEYCODE_DPAD_DOWN, 0x51);  // TK_DOWN
        put(KeyEvent.KEYCODE_DPAD_UP, 0x52);    // TK_UP

        put(KeyEvent.KEYCODE_SHIFT_LEFT, 0x70); // TK_SHIFT
        put(KeyEvent.KEYCODE_SHIFT_RIGHT, 0x70);
        put(KeyEvent.KEYCODE_CTRL_LEFT, 0x71);  // TK_CONTROL
        put(KeyEvent.KEYCODE_CTRL_RIGHT, 0x71);
        put(KeyEvent.KEYCODE_ALT_LEFT, 0x72);   // TK_ALT
        put(KeyEvent.KEYCODE_ALT_RIGHT, 0x72);
    }

    /** Возвращает 0 для клавиш, которых терминал не знает. */
    static int toTerminal(int androidCode) {
        return MAP.get(androidCode, 0);
    }

    private AndroidKeys() { }
}
