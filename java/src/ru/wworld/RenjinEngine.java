package ru.wworld;

import java.io.FileReader;
import java.io.Reader;
import javax.script.ScriptEngine;
import javax.script.ScriptEngineManager;

/** Renjin как движок геометрии внутри приложения.
 *
 *  geometry.R грузится как библиотека (ww.embedded) и опрашивается вызовами
 *  dispatch — канал stdin интерпретатору не нужен. Один и тот же класс
 *  работает и на настольной JVM, и на Android. */
public class RenjinEngine implements GeometryEngine {

    private final ScriptEngine engine;

    public RenjinEngine(Reader geometryScript) throws Exception {
        ScriptEngine e = new ScriptEngineManager().getEngineByName("Renjin");
        if (e == null) {
            throw new IllegalStateException(
                "движок Renjin не найден в classpath — проверьте jar");
        }
        this.engine = e;
        engine.eval("ww.embedded <- TRUE");
        engine.eval(geometryScript);
        engine.eval("srv <- WwGeometryServer$new()");
    }

    public RenjinEngine(String geometryPath) throws Exception {
        this(new FileReader(geometryPath));
    }

    @Override
    public String ask(String command) {
        try {
            // Команда передаётся привязкой, а не склейкой строки запроса:
            // в ней бывают кавычки и очень длинные поля карты.
            engine.put("ww.line", command);
            Object r = engine.eval("srv$dispatch(ww.line)");
            if (r instanceof org.renjin.sexp.StringVector) {
                return ((org.renjin.sexp.StringVector) r).getElementAsString(0);
            }
            return String.valueOf(r);
        } catch (Throwable t) {
            String msg = t.getMessage();
            if (msg != null) msg = msg.replace('\n', ' ');
            return "ERR " + t.getClass().getSimpleName() + ": " + msg;
        }
    }
}
