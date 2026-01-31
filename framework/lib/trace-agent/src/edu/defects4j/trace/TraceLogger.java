package edu.defects4j.trace;

import java.io.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Thread-safe logger for method execution traces.
 * Tracks call/exit with proper indentation per thread.
 */
public class TraceLogger {
    private static PrintWriter writer;
    private static final ConcurrentHashMap<String, AtomicInteger> threadDepth = new ConcurrentHashMap<>();
    private static final String INDENT = "  ";
    private static boolean enabled = true;
    
    static {
        String outFile = System.getProperty("trace.output", "trace.log");
        try {
            writer = new PrintWriter(new BufferedWriter(new FileWriter(outFile), 65536));
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                close();
            }));
        } catch (IOException e) {
            System.err.println("[TraceLogger] Failed to open output file: " + outFile);
            e.printStackTrace();
            enabled = false;
        }
    }
    
    /**
     * Log method entry.
     * Format: [Thread:name] <indent>Call package.class::method(params) (file:line)
     */
    public static void logEntry(String className, String methodName, String methodSig, 
                                 String sourceFile, int lineNumber) {
        if (!enabled) return;
        
        String threadName = Thread.currentThread().getName();
        AtomicInteger depth = threadDepth.computeIfAbsent(threadName, k -> new AtomicInteger(0));
        int currentDepth = depth.getAndIncrement();
        
        StringBuilder sb = new StringBuilder();
        sb.append("[Thread:").append(threadName).append("] ");
        
        for (int i = 0; i < currentDepth; i++) {
            sb.append(INDENT);
        }
        
        sb.append("Call ").append(className).append("::").append(methodName);
        if (methodSig != null && !methodSig.isEmpty()) {
            sb.append(methodSig);
        }
        sb.append(" (").append(sourceFile).append(":").append(lineNumber).append(")");
        
        writeLine(sb.toString());
    }
    
    /**
     * Log method exit.
     * Format: [Thread:name] <indent>Exit package.class::method(params) (file:line)
     */
    public static void logExit(String className, String methodName, String methodSig,
                                String sourceFile, int lineNumber) {
        if (!enabled) return;
        
        String threadName = Thread.currentThread().getName();
        AtomicInteger depth = threadDepth.get(threadName);
        
        int currentDepth = 0;
        if (depth != null) {
            currentDepth = depth.decrementAndGet();
            if (currentDepth < 0) {
                depth.set(0);
                currentDepth = 0;
            }
        }
        
        StringBuilder sb = new StringBuilder();
        sb.append("[Thread:").append(threadName).append("] ");
        
        for (int i = 0; i < currentDepth; i++) {
            sb.append(INDENT);
        }
        
        sb.append("Exit ").append(className).append("::").append(methodName);
        if (methodSig != null && !methodSig.isEmpty()) {
            sb.append(methodSig);
        }
        sb.append(" (").append(sourceFile).append(":").append(lineNumber).append(")");
        
        writeLine(sb.toString());
    }
    
    private static synchronized void writeLine(String line) {
        if (writer != null) {
            writer.println(line);
        }
    }
    
    public static synchronized void flush() {
        if (writer != null) {
            writer.flush();
        }
    }
    
    public static synchronized void close() {
        if (writer != null) {
            writer.flush();
            writer.close();
            writer = null;
        }
    }
}
