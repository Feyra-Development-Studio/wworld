package ru.wworld;

import android.content.res.AssetManager;
import android.util.Log;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;

/**
 * Сборка карты на устройстве.
 *
 * В приложение кладётся не готовая карта, а граф подземелья — описание того,
 * из чего оно состоит: комнаты, коридоры, связи. Растр по этому графу
 * собирается здесь, на телефоне, движком R.
 *
 * Смысл не в экономии места, хотя граф и меньше выгрузки. Смысл в том, что R
 * у нас — вычислитель, а не проверяльщик: операции над целыми построениями
 * (маски комнат, векторы коридоров, вывод стен) живут в geometry.R, и
 * подменять их на телефоне заранее посчитанным ответом значило бы иметь на
 * Android другую игру.
 *
 * Byte-in-byte совпадение с настольной сборкой проверено отдельно
 * (RebuildCheck): те же десять этажей, тот же seed, тот же растр.
 */
final class MapPreparer {

    private static final String TAG = "wworld";

    /**
     * Готовит выгрузку карты в каталоге приложения и возвращает путь к ней.
     *
     * Если выгрузка уже собрана прошлым запуском, работа не повторяется:
     * поднять Renjin и пересчитать десять этажей — секунды, и тратить их на
     * каждый запуск незачем.
     */
    static String prepare(AssetManager assets, File filesDir) throws Exception {
        File csvDir = new File(filesDir, "csv");
        File index = new File(csvDir, "index.csv");

        if (index.exists() && index.length() > 0) {
            Log.i(TAG, "карта уже собрана: " + csvDir);
            return csvDir.getAbsolutePath();
        }

        csvDir.mkdirs();

        long started = System.currentTimeMillis();
        JSONObject dungeon = new JSONObject(readAsset(assets, "dungeon.json"));

        // geometry.R читается из ресурсов: это тот же файл, что на настольных
        // платформах, и расходиться они не должны.
        GeometryEngine engine;
        try (Reader script = new InputStreamReader(
                assets.open("geometry.R"), StandardCharsets.UTF_8)) {
            engine = new RenjinEngine(script);
        }
        Log.i(TAG, "движок R поднят за " + (System.currentTimeMillis() - started) + " мс");

        long building = System.currentTimeMillis();
        List<MapBuilder.Level> levels = new MapBuilder(engine).buildAll(dungeon);
        Log.i(TAG, "собрано этажей: " + levels.size()
                + " за " + (System.currentTimeMillis() - building) + " мс");

        StringBuilder indexCsv = new StringBuilder(
                "level,sheet,owner_sheet,width,height,seed,rooms,corridors,forks,links,"
                + "stair_up_x,stair_up_y,stair_down_x,stair_down_y\n");

        int seed = dungeon.optInt("seed", 0);
        for (MapBuilder.Level level : levels) {
            String sheet = String.format(Locale.ROOT, "level_%02d.csv", level.number);
            write(new File(csvDir, sheet), level.toCsv());

            indexCsv.append(String.format(Locale.ROOT,
                    "%d,%s,%s,%d,%d,%d,0,0,0,0,%d,%d,%d,%d%n",
                    level.number, sheet,
                    String.format(Locale.ROOT, "level_%02d_owner.csv", level.number),
                    level.width, level.height, seed,
                    level.stairUpX, level.stairUpY, level.stairDownX, level.stairDownY));
        }

        // Индекс пишется последним: игра ищет именно его, и незаконченная
        // выгрузка при следующем запуске не сойдёт за готовую.
        write(index, indexCsv.toString());

        Log.i(TAG, "карта собрана за " + (System.currentTimeMillis() - started) + " мс: " + csvDir);
        return csvDir.getAbsolutePath();
    }

    private static String readAsset(AssetManager assets, String name) throws Exception {
        try (InputStream in = assets.open(name)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[16384];
            int read;
            while ((read = in.read(buffer)) > 0) out.write(buffer, 0, read);
            return out.toString("UTF-8");
        }
    }

    private static void write(File file, String text) throws Exception {
        try (Writer writer = new OutputStreamWriter(
                new FileOutputStream(file), StandardCharsets.UTF_8)) {
            writer.write(text);
        }
    }

    private MapPreparer() { }
}
