// Движок геометрии на Renjin.
//
// Это не сервер. Программа ведёт себя ровно как Rscript: её запускают
// дочерним процессом, она читает команды из stdin построчно и пишет ответы
// в stdout. Ни сокетов, ни портов, ни фонового демона — приложение
// клиентское, и второй половине этого не нужно знать ничего, кроме двух
// каналов.
//
// Отличие от Rscript только в том, что интерпретатор R живёт на JVM:
// geometry.R грузится как библиотека (ww.embedded), после чего опрашивается
// вызовами dispatch. Канал stdin остаётся у Java, самому R он не нужен.
//
//   javac -cp renjin.jar -d classes RenjinHost.java
//   java  -cp renjin.jar:classes RenjinHost scripts/geometry.R

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.InputStreamReader;
import java.io.PrintStream;
import javax.script.ScriptEngine;
import javax.script.ScriptEngineManager;

public class RenjinHost {

    private final ScriptEngine engine;

    private RenjinHost() {
        ScriptEngine e = new ScriptEngineManager().getEngineByName("Renjin");
        if (e == null) {
            throw new IllegalStateException(
                "движок Renjin не найден в classpath — проверьте jar");
        }
        this.engine = e;
    }

    private void load(String scriptPath) throws Exception {
        engine.eval("ww.embedded <- TRUE");
        engine.eval(new FileReader(scriptPath));
        engine.eval("srv <- WwGeometryServer$new()");
    }

    private String ask(String command) {
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

    private void serve() throws Exception {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        PrintStream out = System.out;
        String line;
        while ((line = in.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) continue;
            if (line.equals("QUIT")) break;
            out.println(ask(line));
            // Без сброса ответ застрянет в буфере, и вызывающая сторона
            // будет ждать вечно: канал блокирующий.
            out.flush();
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("нужен путь к geometry.R");
            System.exit(2);
        }
        RenjinHost host = new RenjinHost();
        host.load(args[0]);
        host.serve();
    }
}
