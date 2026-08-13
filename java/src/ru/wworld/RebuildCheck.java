package ru.wworld;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import org.json.JSONObject;

/** Сверка: карта, собранная на Java через Renjin, против выгрузки Pascal.
 *
 *  Проверяется то, что поедет на Android: там генератора не будет, в
 *  приложении лежит только граф, и карта собирается на месте. Если сборка
 *  разойдётся с настольной хоть на клетку, подземелья на телефоне и на
 *  компьютере при одном seed окажутся разными.
 *
 *    java -cp ... ru.wworld.RebuildCheck geometry.R out/dungeon.json out/csv */
public class RebuildCheck {

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("нужны: geometry.R, dungeon.json, каталог выгрузки CSV");
            System.err.println("необязательный четвёртый аргумент — команда движка;");
            System.err.println("без него берётся Renjin внутри этой же JVM");
            System.exit(2);
        }
        String geometry = args[0], dungeonPath = args[1], csvDir = args[2];
        String engineCommand = args.length > 3 ? args[3] : null;

        JSONObject dungeon = new JSONObject(
            new String(Files.readAllBytes(Paths.get(dungeonPath)), StandardCharsets.UTF_8));

        long t0 = System.currentTimeMillis();
        GeometryEngine engine = engineCommand == null
            ? new RenjinEngine(geometry)
            : new ProcessEngine(engineCommand, geometry);
        MapBuilder builder = new MapBuilder(engine);
        System.out.printf("движок (%s) поднят за %d мс%n",
                          engineCommand == null ? "Renjin в этой JVM" : engineCommand,
                          System.currentTimeMillis() - t0);

        t0 = System.currentTimeMillis();
        List<MapBuilder.Level> levels = builder.buildAll(dungeon);
        System.out.printf("собрано этажей: %d за %d мс%n", levels.size(),
                          System.currentTimeMillis() - t0);

        int bad = 0;
        for (MapBuilder.Level lv : levels) {
            Path ref = Paths.get(csvDir, String.format("level_%02d.csv", lv.number));
            String expected = new String(Files.readAllBytes(ref), StandardCharsets.UTF_8);
            String actual = lv.toCsv();
            if (expected.equals(actual)) {
                System.out.printf("  этаж %2d: совпал (%dx%d)%n", lv.number, lv.width, lv.height);
            } else {
                bad++;
                System.out.printf("  этаж %2d: РАСХОЖДЕНИЕ%n", lv.number);
                report(expected, actual, lv);
            }
        }
        if (bad == 0) {
            System.out.println("СОВПАДАЕТ: сборка на Java через Renjin равна выгрузке Pascal");
        } else {
            System.out.printf("этажей с расхождением: %d%n", bad);
        }
        System.exit(bad == 0 ? 0 : 1);
    }

    /** Первые несовпавшие клетки — чтобы по логу было видно характер поломки. */
    private static void report(String expected, String actual, MapBuilder.Level lv) {
        String[] e = expected.split("\n"), a = actual.split("\n");
        int shown = 0;
        for (int y = 0; y < Math.min(e.length, a.length) && shown < 5; y++) {
            if (e[y].equals(a[y])) continue;
            String[] ec = e[y].split(","), ac = a[y].split(",");
            for (int x = 0; x < Math.min(ec.length, ac.length) && shown < 5; x++) {
                if (!ec[x].equals(ac[x])) {
                    System.out.printf("    x=%d y=%d: ожидалось %s, получено %s%n",
                                      x, y, ec[x], ac[x]);
                    shown++;
                }
            }
        }
        if (e.length != a.length) {
            System.out.printf("    строк: ожидалось %d, получено %d%n", e.length, a.length);
        }
    }
}
