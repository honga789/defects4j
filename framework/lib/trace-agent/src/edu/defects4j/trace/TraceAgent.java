package edu.defects4j.trace;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;

import javassist.*;

/**
 * Java Agent for tracing method execution.
 * Instruments bytecode to log Call/Exit for each method.
 * 
 * Usage: -javaagent:trace-agent.jar[=options]
 * Options:
 *   filter=package.prefix  - Only instrument classes matching this prefix
 *   
 * System properties:
 *   trace.output=/path/to/file.log  - Output file for traces
 */
public class TraceAgent {
    
    private static String packageFilter = null;
    
    public static void premain(String agentArgs, Instrumentation inst) {
        System.out.println("[TraceAgent] Initializing...");
        
        // Parse agent arguments
        if (agentArgs != null && !agentArgs.isEmpty()) {
            String[] args = agentArgs.split(",");
            for (String arg : args) {
                String[] kv = arg.split("=", 2);
                if (kv.length == 2) {
                    String key = kv[0].trim();
                    String value = kv[1].trim();
                    
                    if ("filter".equals(key)) {
                        packageFilter = value.replace('.', '/');
                        System.out.println("[TraceAgent] Package filter: " + value);
                    }
                }
            }
        }
        
        String outputFile = System.getProperty("trace.output", "trace.log");
        System.out.println("[TraceAgent] Output file: " + outputFile);
        
        inst.addTransformer(new MethodTraceTransformer());
        System.out.println("[TraceAgent] Transformer registered");
    }
    
    static class MethodTraceTransformer implements ClassFileTransformer {
        
        private final ClassPool classPool;
        
        public MethodTraceTransformer() {
            classPool = ClassPool.getDefault();
            // Add common classpaths
            classPool.appendSystemPath();
        }
        
        @Override
        public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                                ProtectionDomain protectionDomain, byte[] classfileBuffer) {
            
            // Skip null class names
            if (className == null) {
                return null;
            }
            
            // Skip system and library classes
            if (shouldSkipClass(className)) {
                return null;
            }
            
            // Apply package filter if specified
            if (packageFilter != null && !className.startsWith(packageFilter)) {
                return null;
            }
            
            try {
                return instrumentClass(className, classfileBuffer, loader);
            } catch (Exception e) {
                // Silently skip classes that fail to instrument
                // System.err.println("[TraceAgent] Failed to instrument: " + className + " - " + e.getMessage());
                return null;
            }
        }
        
        private boolean shouldSkipClass(String className) {
            return className.startsWith("java/") ||
                   className.startsWith("javax/") ||
                   className.startsWith("sun/") ||
                   className.startsWith("jdk/") ||
                   className.startsWith("com/sun/") ||
                   className.startsWith("org/xml/") ||
                   className.startsWith("org/w3c/") ||
                   className.startsWith("javassist/") ||
                   className.startsWith("edu/defects4j/trace/") ||
                   className.contains("$$") ||  // Skip generated classes (proxies, lambdas)
                   className.contains("$Lambda") ||
                   className.startsWith("org/junit/") ||
                   className.startsWith("junit/") ||
                   className.startsWith("org/hamcrest/") ||
                   className.startsWith("org/mockito/");
        }
        
        private byte[] instrumentClass(String className, byte[] classfileBuffer, ClassLoader loader) 
                throws Exception {
            
            String dotClassName = className.replace('/', '.');
            
            // Create a new ClassPool for this class to avoid conflicts
            ClassPool pool = new ClassPool(true);
            pool.appendSystemPath();
            
            if (loader != null) {
                pool.appendClassPath(new LoaderClassPath(loader));
            }
            
            CtClass cc = pool.makeClass(new java.io.ByteArrayInputStream(classfileBuffer));
            
            if (cc.isInterface() || cc.isAnnotation() || cc.isEnum()) {
                cc.detach();
                return null;
            }
            
            boolean modified = false;
            String sourceFile = cc.getClassFile().getSourceFile();
            if (sourceFile == null) {
                sourceFile = className.substring(className.lastIndexOf('/') + 1) + ".java";
            }
            
            for (CtMethod method : cc.getDeclaredMethods()) {
                // Skip abstract, native, and synthetic methods
                int modifiers = method.getModifiers();
                if (Modifier.isAbstract(modifiers) || Modifier.isNative(modifiers)) {
                    continue;
                }
                
                try {
                    instrumentMethod(method, dotClassName, sourceFile);
                    modified = true;
                } catch (CannotCompileException e) {
                    // Skip methods that can't be instrumented
                }
            }
            
            // Also instrument constructors
            for (CtConstructor constructor : cc.getDeclaredConstructors()) {
                int modifiers = constructor.getModifiers();
                if (Modifier.isAbstract(modifiers)) {
                    continue;
                }
                
                try {
                    instrumentConstructor(constructor, dotClassName, sourceFile);
                    modified = true;
                } catch (CannotCompileException e) {
                    // Skip constructors that can't be instrumented
                }
            }
            
            if (modified) {
                byte[] bytecode = cc.toBytecode();
                cc.detach();
                return bytecode;
            }
            
            cc.detach();
            return null;
        }
        
        private void instrumentMethod(CtMethod method, String className, String sourceFile) 
                throws CannotCompileException {
            
            String methodName = method.getName();
            String methodSig = getMethodSignature(method);
            int lineNumber = method.getMethodInfo().getLineNumber(0);
            if (lineNumber < 0) lineNumber = 0;
            
            // Entry logging
            String entryCode = String.format(
                "edu.defects4j.trace.TraceLogger.logEntry(\"%s\", \"%s\", \"%s\", \"%s\", %d);",
                escapeString(className),
                escapeString(methodName),
                escapeString(methodSig),
                escapeString(sourceFile),
                lineNumber
            );
            
            // Exit logging
            String exitCode = String.format(
                "edu.defects4j.trace.TraceLogger.logExit(\"%s\", \"%s\", \"%s\", \"%s\", %d);",
                escapeString(className),
                escapeString(methodName),
                escapeString(methodSig),
                escapeString(sourceFile),
                lineNumber
            );
            
            method.insertBefore(entryCode);
            method.insertAfter(exitCode, true);  // true = also run on exception
        }
        
        private void instrumentConstructor(CtConstructor constructor, String className, String sourceFile) 
                throws CannotCompileException {
            
            String methodName = "<init>";
            String methodSig = getConstructorSignature(constructor);
            int lineNumber = constructor.getMethodInfo().getLineNumber(0);
            if (lineNumber < 0) lineNumber = 0;
            
            // Entry logging
            String entryCode = String.format(
                "edu.defects4j.trace.TraceLogger.logEntry(\"%s\", \"%s\", \"%s\", \"%s\", %d);",
                escapeString(className),
                escapeString(methodName),
                escapeString(methodSig),
                escapeString(sourceFile),
                lineNumber
            );
            
            // Exit logging
            String exitCode = String.format(
                "edu.defects4j.trace.TraceLogger.logExit(\"%s\", \"%s\", \"%s\", \"%s\", %d);",
                escapeString(className),
                escapeString(methodName),
                escapeString(methodSig),
                escapeString(sourceFile),
                lineNumber
            );
            
            constructor.insertBefore(entryCode);
            constructor.insertAfter(exitCode, true);
        }
        
        private String getMethodSignature(CtMethod method) {
            try {
                StringBuilder sb = new StringBuilder("(");
                CtClass[] paramTypes = method.getParameterTypes();
                for (int i = 0; i < paramTypes.length; i++) {
                    if (i > 0) sb.append(",");
                    sb.append(getSimpleTypeName(paramTypes[i]));
                }
                sb.append(")");
                return sb.toString();
            } catch (NotFoundException e) {
                return "()";
            }
        }
        
        private String getConstructorSignature(CtConstructor constructor) {
            try {
                StringBuilder sb = new StringBuilder("(");
                CtClass[] paramTypes = constructor.getParameterTypes();
                for (int i = 0; i < paramTypes.length; i++) {
                    if (i > 0) sb.append(",");
                    sb.append(getSimpleTypeName(paramTypes[i]));
                }
                sb.append(")");
                return sb.toString();
            } catch (NotFoundException e) {
                return "()";
            }
        }
        
        private String getSimpleTypeName(CtClass type) {
            String name = type.getName();
            int lastDot = name.lastIndexOf('.');
            if (lastDot >= 0) {
                return name.substring(lastDot + 1);
            }
            return name;
        }
        
        private String escapeString(String s) {
            if (s == null) return "";
            return s.replace("\\", "\\\\").replace("\"", "\\\"");
        }
    }
}
