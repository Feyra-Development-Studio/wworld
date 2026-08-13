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
//   javac -cp renjin.jar:json.jar -d classes java/src/ru/wworld/*.java
//   java  -cp renjin.jar:json.jar:classes ru.wworld.RenjinHost scripts/geometry.R

package ru.wworld;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintStream;

public class RenjinHost {

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("нужен путь к geometry.R");
            System.exit(2);
        }
        GeometryEngine engine = new RenjinEngine(args[0]);
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        PrintStream out = System.out;
        String line;
        while ((line = in.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) continue;
            if (line.equals("QUIT")) break;
            out.println(engine.ask(line));
            // Без сброса ответ застрянет в буфере, и вызывающая сторона будет
            // ждать вечно: канал блокирующий.
            out.flush();
        }
    }
}
