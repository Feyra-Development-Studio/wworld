package ru.wworld;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Движок геометрии как дочерний процесс — тот же способ, что у Pascal.
 *
 *  Нужен и сам по себе (запустить GNU R из Java), и для проверок: сборщик
 *  карты можно прогнать на GNU R и сверить с выгрузкой, не привлекая Renjin.
 *  Никакого сервера здесь тоже нет — два канала до дочернего процесса. */
public class ProcessEngine implements GeometryEngine, AutoCloseable {

    private final Process process;
    private final BufferedReader in;
    private final BufferedWriter out;

    public ProcessEngine(String command, String geometryPath) throws Exception {
        List<String> argv = new ArrayList<>();
        for (String part : command.trim().split(" ")) {
            if (!part.isEmpty()) argv.add(part);
        }
        argv.add(geometryPath);
        ProcessBuilder pb = new ProcessBuilder(argv);
        pb.redirectErrorStream(false);
        process = pb.start();
        in = new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8));
        out = new BufferedWriter(new OutputStreamWriter(process.getOutputStream(), StandardCharsets.UTF_8));
    }

    @Override
    public String ask(String command) {
        try {
            out.write(command);
            out.write('\n');
            out.flush();
            String reply = in.readLine();
            return reply == null ? "ERR движок закрыл канал" : reply;
        } catch (Exception e) {
            return "ERR " + e.getClass().getSimpleName() + ": " + e.getMessage();
        }
    }

    @Override
    public void close() throws Exception {
        try {
            out.write("QUIT\n");
            out.flush();
        } catch (Exception ignored) {
            // движок мог уже умереть — гасим молча
        }
        process.waitFor();
    }
}
