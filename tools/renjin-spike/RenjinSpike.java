// Прогон geometry.R под Renjin.
//
// Скрипт грузится как библиотека (ww.embedded), затем опрашивается вызовами
// dispatch — ровно так, как это будет делать встроенный движок на Android.
// Канал stdin при этом не используется вовсе: на JVM его в привычном виде
// может не оказаться, и завязываться на него нельзя.
//
// Запуск (JDK 11+ умеет исходник напрямую):
//   java -cp renjin-script-engine.jar RenjinSpike.java geometry.R commands.txt

import java.io.FileReader;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;
import javax.script.ScriptEngine;
import javax.script.ScriptEngineManager;

public class RenjinSpike {

    private final ScriptEngine engine;

    private RenjinSpike() {
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
            Object r = engine.eval("srv$dispatch(\"" + command + "\")");
            return String.valueOf(
                r instanceof org.renjin.sexp.StringVector
                    ? ((org.renjin.sexp.StringVector) r).getElementAsString(0)
                    : r);
        } catch (Throwable t) {
            // Ошибку печатаем в поток вывода: сверка построчная, и упавшая
            // команда должна быть видна на своём месте, а не потеряться.
            String msg = t.getMessage();
            if (msg != null) msg = msg.replace('\n', ' ');
            return "ОШИБКА " + t.getClass().getSimpleName() + ": " + msg;
        }
    }

    private void run(String scriptPath, String commandsPath) throws Exception {
        load(scriptPath);
        List<String> lines = Files.readAllLines(Paths.get(commandsPath));
        for (String line : lines) {
            if (line.trim().isEmpty()) continue;
            System.out.println(ask(line.trim()));
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("нужны два аргумента: geometry.R и файл команд");
            System.exit(2);
        }
        new RenjinSpike().run(args[0], args[1]);
    }
}
