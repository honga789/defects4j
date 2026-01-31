package edu.defects4j.trace;

import org.junit.runner.JUnitCore;
import org.junit.runner.Request;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;

/**
 * A simple runner that can execute a single test method.
 * 
 * Usage: java SingleTestRunner <ClassName> [methodName]
 *   - If methodName is provided, runs only that method
 *   - If methodName is not provided, runs all tests in the class
 */
public class SingleTestRunner {
    
    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: SingleTestRunner <ClassName> [methodName]");
            System.exit(1);
        }
        
        String className = args[0];
        String methodName = args.length > 1 ? args[1] : null;
        
        try {
            Class<?> testClass = Class.forName(className);
            Result result;
            
            if (methodName != null && !methodName.isEmpty()) {
                // Run single method
                System.out.println("[SingleTestRunner] Running: " + className + "#" + methodName);
                Request request = Request.method(testClass, methodName);
                result = new JUnitCore().run(request);
            } else {
                // Run all methods in class
                System.out.println("[SingleTestRunner] Running all tests in: " + className);
                result = JUnitCore.runClasses(testClass);
            }
            
            // Print summary
            System.out.println("\n=== Test Results ===");
            System.out.println("Tests run: " + result.getRunCount());
            System.out.println("Failures: " + result.getFailureCount());
            System.out.println("Ignored: " + result.getIgnoreCount());
            System.out.println("Time: " + result.getRunTime() + "ms");
            
            if (!result.wasSuccessful()) {
                System.out.println("\nFailures:");
                for (Failure failure : result.getFailures()) {
                    System.out.println("  - " + failure.getTestHeader());
                    System.out.println("    " + failure.getMessage());
                }
            }
            
            System.exit(result.wasSuccessful() ? 0 : 1);
            
        } catch (ClassNotFoundException e) {
            System.err.println("Error: Class not found: " + className);
            System.exit(1);
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
