package ru.wworld;

import java.io.FileReader;
import java.io.StringReader;
import java.io.Reader;
import org.renjin.eval.Context;
import org.renjin.eval.Session;
import org.renjin.eval.SessionBuilder;
import org.renjin.parser.RParser;
import org.renjin.sexp.ExpressionVector;
import org.renjin.sexp.SEXP;
import org.renjin.sexp.StringArrayVector;
import org.renjin.sexp.StringVector;
import org.renjin.sexp.Symbol;

/** Renjin как движок геометрии внутри приложения.
 *
 *  geometry.R грузится как библиотека (ww.embedded) и опрашивается вызовами
 *  dispatch — канал stdin интерпретатору не нужен. Один и тот же класс
 *  работает и на настольной JVM, и на Android. */
public class RenjinEngine implements GeometryEngine {

    /** Порождает ли Renjin байт-код во время работы.
     *
     *  У Renjin два таких места, и оба ведут в ClassLoader.defineClass с сырым
     *  байт-кодом JVM: компиляция циклов R после 200 итераций
     *  (ForFunction.COMPILE_LOOPS) и сплавление операций над векторами в
     *  конвейере (pipeliner.fusion). На ART сырой байт-код JVM не грузится
     *  вовсе — там нужен dex, — поэтому на телефоне такой путь не «работает
     *  медленнее», а падает, причём отложенно: короткий цикл пройдёт, длинный
     *  уронит.
     *
     *  Опасен из них по-настоящему второй. Компиляция циклов у Renjin и так
     *  выключена по умолчанию — COMPILE_LOOPS читается из свойства
     *  renjin.compile.loops, которого никто не ставит. А вот сплавление в
     *  конвейере включено, и выключателем ему служит наличие свойства
     *  renjin.vp.disablejit.
     *
     *  Оба выключателя предусмотрены самим Renjin, чинить форк не нужно.
     *  Замер показал, что на нашей нагрузке кодогенерация не срабатывает и
     *  так: ни JitClassLoader, ни ClassWriter из ASM не загружаются, а десять
     *  этажей собираются за одно и то же время с ней и без неё. То есть
     *  выключение ничего не стоит, но снимает мину, которая иначе ждала бы
     *  подземелья покрупнее. */
    private static void disableBytecodeGeneration() {
        // Свойство читается один раз при инициализации LoopKernels, поэтому
        // выставлять его нужно до того, как загрузится хоть один класс
        // конвейера. Проверяется на «не null», а не на значение.
        System.setProperty("renjin.vp.disablejit", "true");
        org.renjin.primitives.special.ForFunction.COMPILE_LOOPS = false;
    }

    /** Android узнаётся по имени виртуальной машины: на ART это Dalvik.
     *
     *  Через android.os.Build было бы нагляднее, но тогда класс перестанет
     *  собираться для настольной части, а он один на обе. */
    private static boolean runningOnArt() {
        String vm = System.getProperty("java.vm.name", "");
        String vendor = System.getProperty("java.vendor", "");
        return vm.toLowerCase().contains("dalvik") || vendor.contains("Android");
    }

    static {
        // Настольная сборка оставляет кодогенерацию включённой: там она
        // работает штатно, и замер быстродействия для выбора среды R (#4)
        // должен видеть Renjin таким, какой он есть. Принудительно выключить
        // можно свойством -Dwworld.renjin.jit=off.
        if (runningOnArt() || "off".equals(System.getProperty("wworld.renjin.jit"))) {
            disableBytecodeGeneration();
        }
    }

    private final Session session;
    private final Context context;

    /* Renjin поднимается напрямую, без javax.script.
     *
     * JSR-223 на Android не существует: пакета javax.script в системе нет
     * вовсе, и сборка приложения на нём останавливается. Прямой путь через
     * Session и Context доступен одинаково на настольной JVM и на ART, а
     * значит движок остаётся один на обе платформы — а не два похожих, за
     * расхождением которых пришлось бы следить. */
    public RenjinEngine(Reader geometryScript) throws Exception {
        session = new SessionBuilder().withDefaultPackages().build();
        context = session.getTopLevelContext();

        eval("ww.embedded <- TRUE");
        context.evaluate(RParser.parseAllSource(geometryScript));
        eval("srv <- WwGeometryServer$new()");
    }

    private SEXP eval(String source) throws Exception {
        ExpressionVector expressions = RParser.parseAllSource(new StringReader(source));
        return context.evaluate(expressions);
    }

    public RenjinEngine(String geometryPath) throws Exception {
        this(new FileReader(geometryPath));
    }

    @Override
    public String ask(String command) {
        try {
            // Команда кладётся в окружение, а не склеивается в строку запроса:
            // в ней бывают кавычки и очень длинные поля карты.
            session.getGlobalEnvironment().setVariable(
                context, Symbol.get("ww.line"), new StringArrayVector(command));
            SEXP r = eval("srv$dispatch(ww.line)");
            if (r instanceof StringVector) {
                return ((StringVector) r).getElementAsString(0);
            }
            return String.valueOf(r);
        } catch (Throwable t) {
            String msg = t.getMessage();
            if (msg != null) msg = msg.replace('\n', ' ');
            return "ERR " + t.getClass().getSimpleName() + ": " + msg;
        }
    }
}
