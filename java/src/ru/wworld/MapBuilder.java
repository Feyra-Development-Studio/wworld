package ru.wworld;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Сборка растровой карты этажа из графа-инструкции.
 *
 *  Повторяет wwRebuild.pas клетка в клетку — и это проверяется в CI сверкой с
 *  выгрузкой, сделанной на Pascal. Порядок штамповки задаётся возрастанием
 *  идентификатора: он выдаётся строго по ходу построения, поэтому именно так
 *  воспроизводится исходная карта.
 *
 *  Нужен на Android: генератор туда не едет, в приложении лежит только граф,
 *  а клетки считает Renjin по тем же запросам, что и на десктопе. */
public class MapBuilder {

    public static final int ROCK = 0, WALL = 1, ROOM = 2;
    public static final int COR_MINOR = 3, COR_SECOND = 4, COR_MAIN = 5;
    public static final int JUNCTION = 6, FORK = 7, STAIR_UP = 8, STAIR_DOWN = 9;
    private static final int NO_OWNER = -1;

    private final GeometryEngine engine;

    public MapBuilder(GeometryEngine engine) {
        this.engine = engine;
    }

    /** Один этаж: коды клеток и координаты лестниц. */
    public static class Level {
        public int number, width, height;
        public int stairUpX, stairUpY, stairDownX, stairDownY;
        public int[] code;
        public int[] owner;

        public int at(int x, int y) { return code[y * width + x]; }

        public String toCsv() {
            StringBuilder sb = new StringBuilder();
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    if (x > 0) sb.append(',');
                    sb.append(code[y * width + x]);
                }
                sb.append('\n');
            }
            return sb.toString();
        }
    }

    /** Запрос формы по её спецификации — той же строкой, что шлёт Pascal. */
    private String shapeRequest(JSONObject room) {
        String shape = room.getString("shape");
        if (!"composite".equals(shape)) {
            int w = room.getInt("w"), h = room.getInt("h");
            if ("square".equals(shape) || "circle".equals(shape)) {
                return "SHAPE " + shape + " " + w;
            }
            return "SHAPE " + shape + " " + w + " " + h;
        }
        JSONArray parts = room.getJSONArray("parts");
        StringBuilder sb = new StringBuilder("COMPOSITE ").append(parts.length());
        for (int i = 0; i < parts.length(); i++) {
            JSONObject p = parts.getJSONObject(i);
            sb.append(' ').append(p.getString("type"))
              .append(' ').append(p.getInt("w"))
              .append(' ').append(p.getInt("h"))
              .append(' ').append(p.getInt("ox"))
              .append(' ').append(p.getInt("oy"));
        }
        return sb.toString();
    }

    private void put(Level lv, int x, int y, int code, int owner) {
        if (x < 0 || y < 0 || x >= lv.width || y >= lv.height) return;
        lv.code[y * lv.width + x] = code;
        lv.owner[y * lv.width + x] = owner;
    }

    private int ownerAt(Level lv, int x, int y) {
        if (x < 0 || y < 0 || x >= lv.width || y >= lv.height) return NO_OWNER;
        return lv.owner[y * lv.width + x];
    }

    private int corridorCode(int rank) {
        if (rank == 1) return COR_MINOR;
        if (rank == 2) return COR_SECOND;
        return COR_MAIN;
    }

    private void stampRoom(Level lv, JSONObject room) {
        String reply = engine.ask(shapeRequest(room));
        String[] f = reply.split(" ");
        if (!"OK".equals(f[0])) {
            throw new IllegalStateException("геометрия отказала: " + reply);
        }
        int w = Integer.parseInt(f[1]), h = Integer.parseInt(f[2]);
        String mask = f[4];
        int x0 = room.getInt("x"), y0 = room.getInt("y"), id = room.getInt("id");
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                if (mask.charAt(y * w + x) == '1') put(lv, x0 + x, y0 + y, ROOM, id);
            }
        }
    }

    private void stampFork(Level lv, JSONObject fork) {
        int rank = fork.getInt("rank"), id = fork.getInt("id");
        int x0 = fork.getInt("x"), y0 = fork.getInt("y");
        for (int y = 0; y < rank; y++) {
            for (int x = 0; x < rank; x++) put(lv, x0 + x, y0 + y, FORK, id);
        }
    }

    private void stampCorridor(Level lv, JSONObject cor, List<Integer> corridorIds) {
        JSONArray path = cor.getJSONArray("path");
        int rank = cor.getInt("rank"), id = cor.getInt("id");
        int from = cor.getInt("from"), to = cor.getInt("to");

        StringBuilder req = new StringBuilder("EXPAND ").append(rank).append(' ').append(path.length());
        for (int i = 0; i < path.length(); i++) {
            JSONArray p = path.getJSONArray(i);
            req.append(' ').append(p.getInt(0)).append(' ').append(p.getInt(1));
        }
        String reply = engine.ask(req.toString());
        String[] f = reply.split(" ");
        if (!"OK".equals(f[0])) {
            throw new IllegalStateException("геометрия отказала: " + reply);
        }
        int n = Integer.parseInt(f[1]);
        for (int i = 0; i < n; i++) {
            int cx = Integer.parseInt(f[2 + i * 2]);
            int cy = Integer.parseInt(f[3 + i * 2]);
            if (cx < 0 || cy < 0 || cx >= lv.width || cy >= lv.height) continue;
            int o = ownerAt(lv, cx, cy);
            if (o == NO_OWNER) {
                put(lv, cx, cy, corridorCode(rank), id);
            } else if (o != from && o != to && corridorIds.contains(o)) {
                // Чужая клетка на пути бывает двух видов: стык с собственным
                // концом сохраняет свой код, а вот пересечение с посторонним
                // коридором помечается перекрёстком.
                lv.code[cy * lv.width + cx] = JUNCTION;
            }
        }
    }

    private void applyWalls(Level lv) {
        StringBuilder digits = new StringBuilder(lv.width * lv.height);
        for (int i = 0; i < lv.code.length; i++) digits.append((char) ('0' + lv.code[i]));
        String reply = engine.ask("WALLS " + lv.width + " " + lv.height + " " + digits);
        String[] f = reply.split(" ");
        if (!"OK".equals(f[0])) {
            throw new IllegalStateException("геометрия отказала: " + reply);
        }
        String out = f[1];
        for (int i = 0; i < lv.code.length; i++) lv.code[i] = out.charAt(i) - '0';
    }

    /** Собирает этаж по его описанию из dungeon.json. */
    public Level build(JSONObject levelJson) {
        Level lv = new Level();
        lv.number = levelJson.getInt("level");
        lv.width = levelJson.getInt("width");
        lv.height = levelJson.getInt("height");
        lv.code = new int[lv.width * lv.height];
        lv.owner = new int[lv.width * lv.height];
        for (int i = 0; i < lv.owner.length; i++) lv.owner[i] = NO_OWNER;

        JSONObject stairs = levelJson.getJSONObject("stairs");
        lv.stairUpX = stairs.getInt("up_x");
        lv.stairUpY = stairs.getInt("up_y");
        lv.stairDownX = stairs.getInt("down_x");
        lv.stairDownY = stairs.getInt("down_y");

        JSONArray rooms = levelJson.getJSONArray("rooms");
        JSONArray forks = levelJson.getJSONArray("forks");
        JSONArray corridors = levelJson.getJSONArray("corridors");

        List<Integer> corridorIds = new ArrayList<>();
        for (int i = 0; i < corridors.length(); i++) {
            corridorIds.add(corridors.getJSONObject(i).getInt("id"));
        }

        // Порядок штамповки — по возрастанию id, то есть по порядку постройки.
        List<JSONObject> all = new ArrayList<>();
        for (int i = 0; i < rooms.length(); i++) all.add(tag(rooms.getJSONObject(i), "room"));
        for (int i = 0; i < forks.length(); i++) all.add(tag(forks.getJSONObject(i), "fork"));
        for (int i = 0; i < corridors.length(); i++) all.add(tag(corridors.getJSONObject(i), "corridor"));
        Collections.sort(all, Comparator.comparingInt(o -> o.getInt("id")));

        for (JSONObject o : all) {
            switch (o.getString("ww.kind")) {
                case "room": stampRoom(lv, o); break;
                case "fork": stampFork(lv, o); break;
                default: stampCorridor(lv, o, corridorIds); break;
            }
        }

        applyWalls(lv);
        if (lv.stairUpX >= 0) lv.code[lv.stairUpY * lv.width + lv.stairUpX] = STAIR_UP;
        if (lv.stairDownX >= 0) lv.code[lv.stairDownY * lv.width + lv.stairDownX] = STAIR_DOWN;
        return lv;
    }

    private JSONObject tag(JSONObject o, String kind) {
        o.put("ww.kind", kind);
        return o;
    }

    /** Все этажи подземелья из разобранного dungeon.json. */
    public List<Level> buildAll(JSONObject dungeon) {
        List<Level> out = new ArrayList<>();
        JSONArray levels = dungeon.getJSONArray("levels");
        for (int i = 0; i < levels.length(); i++) out.add(build(levels.getJSONObject(i)));
        return out;
    }
}
