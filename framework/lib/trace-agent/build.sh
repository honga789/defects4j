#!/bin/bash
# Build script for Trace Agent
# Run inside Docker container: docker-compose exec defects4j bash /defects4j/framework/lib/trace-agent/build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
BUILD_DIR="$SCRIPT_DIR/build"
LIB_DIR="$SCRIPT_DIR/lib"
OUTPUT_JAR="$SCRIPT_DIR/trace-agent.jar"

JAVASSIST_VERSION="3.29.2-GA"
JAVASSIST_JAR="$LIB_DIR/javassist-${JAVASSIST_VERSION}.jar"

echo "=== Building Trace Agent ==="

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$LIB_DIR"

# Download javassist if not exists
if [ ! -f "$JAVASSIST_JAR" ]; then
    echo "Downloading Javassist ${JAVASSIST_VERSION}..."
    curl -L -o "$JAVASSIST_JAR" \
        "https://repo1.maven.org/maven2/org/javassist/javassist/${JAVASSIST_VERSION}/javassist-${JAVASSIST_VERSION}.jar"
fi

# Compile Java files
echo "Compiling Java sources..."

# First compile TraceLogger and TraceAgent (no JUnit dependency)
javac -cp "$JAVASSIST_JAR" \
      -d "$BUILD_DIR" \
      "$SRC_DIR/edu/defects4j/trace/TraceLogger.java" \
      "$SRC_DIR/edu/defects4j/trace/TraceAgent.java"

# Compile SingleTestRunner (needs JUnit 4+)
JUNIT_JAR="$LIB_DIR/junit-4.13.2.jar"
HAMCREST_JAR="$LIB_DIR/hamcrest-core-1.3.jar"

if [ ! -f "$JUNIT_JAR" ]; then
    echo "Downloading JUnit 4.13.2..."
    curl -L -o "$JUNIT_JAR" \
        "https://repo1.maven.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar"
fi

if [ ! -f "$HAMCREST_JAR" ]; then
    echo "Downloading Hamcrest 1.3..."
    curl -L -o "$HAMCREST_JAR" \
        "https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar"
fi

echo "Using JUnit: $JUNIT_JAR"

javac -cp "$JAVASSIST_JAR:$JUNIT_JAR:$HAMCREST_JAR" \
      -d "$BUILD_DIR" \
      "$SRC_DIR/edu/defects4j/trace/SingleTestRunner.java"

# Extract javassist classes into build dir (to bundle in agent jar)
echo "Bundling Javassist classes..."
cd "$BUILD_DIR"
jar xf "$JAVASSIST_JAR"
rm -rf META-INF

# Create the agent JAR
echo "Creating agent JAR..."
cd "$BUILD_DIR"
jar cfm "$OUTPUT_JAR" "$SCRIPT_DIR/MANIFEST.MF" .

echo "=== Build complete: $OUTPUT_JAR ==="
ls -la "$OUTPUT_JAR"
