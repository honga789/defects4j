# Defects4J Execution Trace Generation

This tool generates execution traces for Defects4J bugs by instrumenting Java bytecode and running tests.

## Prerequisites

- Docker environment with Defects4J installed
- Built trace agent: `cd framework/lib/trace-agent && bash build.sh`

## Quick Start

```bash
# Basic usage - generate traces for Math bug #1
bash framework/util/generate_traces.sh -p Math -b 1

# With options
bash framework/util/generate_traces.sh -p Math -b 1 \
    --max-subtests 20 \
    --max-trace-size 1073741824 \
    --max-pass 10 \
    --compress \
    --cleanup
```

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --project` | Project ID (Math, Lang, Chart, etc.) | Required |
| `-b, --bug` | Bug ID (1, 2, 3, ...) | Required |
| `-w, --workdir` | Working directory | `/workspace` |
| `-o, --output` | Output directory for traces | `/workspace/traces` |
| `--max-pass` | Max number of passing tests to run (0 = all) | `0` |
| `--max-subtests` | Max subtests before switching to single method mode | `30` |
| `--max-trace-size` | Max trace file size in bytes (files larger will be deleted) | `1073741824` (1GB) |
| `--timeout` | Max time in seconds per test before killing | `600` (10 min) |
| `--filter` | Package filter for tracing (e.g., "org.apache.commons.math3") | None |
| `--compress` | Compress trace files with gzip after generation | `false` |
| `--cleanup` | Remove working directories after completion | `false` |
| `--skip-pass` | Skip running passing tests (only run failing tests) | `false` |
| `-h, --help` | Show help message | - |

## Output Structure

```
/workspace/traces/Math-1/
├── ground-truth.json          # Bug metadata and modified methods
├── metadata.json              # Trace execution metadata
├── tests_trigger.txt          # List of failing tests
├── tests_all.txt              # List of all tests
├── fail/                      # Failing test traces
│   ├── org_apache_commons_math3_fraction_BigFractionTest_testDigitLimitConstructor.log
│   └── org_apache_commons_math3_fraction_FractionTest_testDigitLimitConstructor.log
└── pass/                      # Passing test traces
    ├── org_apache_commons_math3_util_PrecisionTest.log
    └── ...
```

## Trace Format

Each trace file contains method call/exit events:

```
[Thread:main] Call org.apache.commons.math3.fraction.BigFraction::<init>(int) (BigFraction.java:369)
[Thread:main]   Call org.apache.commons.math3.util.MathUtils::checkNotNull(Object,Localizable,Object[]) (MathUtils.java:251)
[Thread:main]   Exit org.apache.commons.math3.util.MathUtils::checkNotNull(Object,Localizable,Object[]) (MathUtils.java:251)
[Thread:main] Exit org.apache.commons.math3.fraction.BigFraction::<init>(int) (BigFraction.java:369)
```

Format: `[Thread:<name>] <Call|Exit> <package>.<class>::<method>(<params>) (<file>:<line>)`

## ground-truth.json Structure

```json
{
    "version": "Math-1",
    "project_id": "Math",
    "bug_id": 1,
    "files": {
        "src": ["org/apache/commons/math3/fraction/BigFraction.java"],
        "test": ["org/apache/commons/math3/fraction/BigFractionTest.java"]
    },
    "classes": {
        "modified": ["org.apache.commons.math3.fraction.BigFraction"],
        "test": ["org.apache.commons.math3.fraction.BigFractionTest"]
    },
    "functions": [
        "org.apache.commons.math3.fraction.BigFraction::BigFraction(double,double,int,int)"
    ],
    "modified_locations": [
        {
            "file": "org/apache/commons/math3/fraction/BigFraction.java",
            "class": "org.apache.commons.math3.fraction.BigFraction",
            "method": "BigFraction(double,double,int,int)",
            "method_name": "BigFraction",
            "line_start_buggy": 269,
            "line_start_fixed": 269
        }
    ],
    "commit_buggy": "d7fd760eb8c5ba8dc7bc30fd565575f2547e0c86",
    "commit_fixed": "86545dab3ed57872ad98b23e46924d67ddad03fc",
    "report_id": "MATH-996",
    "report_url": "https://issues.apache.org/jira/browse/MATH-996",
    "tests_trigger": [
        "org.apache.commons.math3.fraction.BigFractionTest::testDigitLimitConstructor"
    ],
    "source_dir": "src/main/java",
    "test_dir": "src/test/java"
}
```

## metadata.json Structure

```json
{
    "version": "Math-1",
    "execution": {
        "max_subtests_threshold": 20,
        "max_trace_size_bytes": 1073741824,
        "timeout_seconds": 600,
        "max_pass_tests": 10,
        "compression_enabled": false,
        "package_filter": ""
    },
    "traces": {
        "fail": {
            "count": 2,
            "size_bytes": 100702,
            "run_mode": {
                "full_class_count": 0,
                "single_method_count": 2,
                "single_method_tests": [
                    "org.apache.commons.math3.fraction.BigFractionTest::testDigitLimitConstructor"
                ]
            },
            "skipped_oversized": {
                "count": 0,
                "tests": []
            },
            "skipped_timeout": {
                "count": 0,
                "tests": []
            },
            "files": ["org_apache_commons_math3_fraction_BigFractionTest_testDigitLimitConstructor.log"]
        },
        "pass": {
            "count": 4,
            "size_bytes": 115417292,
            "skipped_large_classes": 0,
            "skipped_oversized": {
                "count": 1,
                "tests": ["org.apache.commons.math3.ode.nonstiff.HighamHall54StepInterpolatorTest"]
            },
            "skipped_timeout": {
                "count": 0,
                "tests": []
            },
            "files": ["org_apache_commons_math3_util_PrecisionTest.log"]
        },
        "total_size_bytes": 115517994
    },
    "paths": {
        "buggy_dir": "/workspace/Math_1_buggy",
        "fixed_dir": "/workspace/Math_1_fixed",
        "trace_output_dir": "/workspace/traces/Math-1"
    },
    "timing": {
        "started_at": "2025-01-15T10:30:00+00:00",
        "finished_at": "2025-01-15T10:45:30+00:00",
        "elapsed_seconds": 930
    }
}
```

## Examples

### Example 1: Generate traces for Math-1 with compression

```bash
docker-compose exec defects4j bash -c \
    "bash /defects4j/framework/util/generate_traces.sh -p Math -b 1 --compress --cleanup"
```

### Example 2: Only failing tests, skip large traces

```bash
docker-compose exec defects4j bash -c \
    "bash /defects4j/framework/util/generate_traces.sh -p Math -b 1 \
    --skip-pass \
    --max-trace-size 524288000"  # 500MB limit
```

### Example 3: Sample 20 passing tests with package filter

```bash
docker-compose exec defects4j bash -c \
    "bash /defects4j/framework/util/generate_traces.sh -p Math -b 1 \
    --max-pass 20 \
    --max-subtests 15 \
    --filter org.apache.commons.math3"
```

### Example 4: Generate for multiple bugs

```bash
for bug_id in {1..5}; do
    docker-compose exec defects4j bash -c \
        "bash /defects4j/framework/util/generate_traces.sh -p Math -b $bug_id \
        --max-pass 10 \
        --compress \
        --cleanup"
done
```

## Trace Size Management

The tool has two mechanisms to prevent excessive trace file sizes:

### 1. Subtest Threshold (`--max-subtests`)

- **For failing tests**: If a test class has more than N subtests, only the specific failing method is run
- **For passing tests**: If a test class has more than N subtests, the entire class is skipped

**Example**: With `--max-subtests 20`:
- `BigFractionTest` has 27 @Test methods → runs only `testDigitLimitConstructor` (the failing one)
- `SomePassingTest` has 50 @Test methods → skipped entirely

### 2. Trace Size Limit (`--max-trace-size`)

After running each test, if the trace file exceeds the size limit, it is deleted and recorded in metadata.

**Example**: With `--max-trace-size 1073741824` (1GB):
- `HessenbergTransformerTest` generates 5GB trace → deleted, recorded in `metadata.json`

## Troubleshooting

### No traces generated

**Issue**: Trace files are empty or not created.

**Solution**: 
- Check that trace agent is built: `ls -lh framework/lib/trace-agent/trace-agent.jar`
- Rebuild if needed: `cd framework/lib/trace-agent && bash build.sh`

### "integer expression expected" error

**Issue**: Bug in counting @Test methods.

**Solution**: This is fixed in the latest version. The count_test_methods function now validates numbers properly.

### Traces too large

**Issue**: Individual tests generate multi-GB traces.

**Solutions**:
- Use `--max-trace-size` to set a limit (default: 1GB)
- Use `--max-subtests` to limit test scope (default: 30)
- Use `--filter` to trace only specific packages
- Use `--compress` to gzip traces after generation

### Out of disk space

**Issue**: Workspace fills up with traces.

**Solutions**:
- Use `--cleanup` to remove buggy/fixed directories after completion
- Use `--skip-pass` to only generate failing test traces
- Process bugs one at a time instead of batching
- Mount workspace to external storage with more space

## Performance Tips

1. **Use package filters** to reduce instrumentation overhead:
   ```bash
   --filter org.apache.commons.math3.fraction
   ```

2. **Limit passing tests** to save time:
   ```bash
   --max-pass 20  # Only run 20 random passing tests
   ```

3. **Skip passing tests** for quick bug analysis:
   ```bash
   --skip-pass
   ```

4. **Clean up as you go**:
   ```bash
   --cleanup --compress
   ```

## Integration with Bug Localization Research

This tool was designed for bug localization research. The trace format is compatible with fault localization techniques that analyze execution paths:

- **Spectrum-based**: Use pass/fail traces to calculate suspiciousness scores
- **Mutation-based**: Compare traces from buggy vs. fixed versions
- **Learning-based**: Extract features from call sequences for ML models

## Building the Trace Agent

The trace agent must be built before first use:

```bash
# Inside Docker container
cd /defects4j/framework/lib/trace-agent
bash build.sh

# Output: trace-agent.jar (~800KB)
```

The build script automatically downloads:
- Javassist 3.29.2-GA (bytecode instrumentation)
- JUnit 4.13.2 (test execution)
- Hamcrest 1.3 (JUnit dependency)

## Technical Details

### Bytecode Instrumentation

The trace agent uses Javassist to inject logging at method entry/exit points:

```java
method.insertBefore("TraceLogger.logEntry(\"" + className + "\", \"" + methodName + "\", ...");
method.insertAfter("TraceLogger.logExit(\"" + className + "\", \"" + methodName + "\", ...");
```

### Test Execution Modes

1. **Full class mode**: `org.junit.runner.JUnitCore ClassName`
   - Runs all @Test methods in the class
   - Used when subtest count ≤ threshold

2. **Single method mode**: `edu.defects4j.trace.SingleTestRunner ClassName methodName`
   - Runs only one @Test method using JUnit's Request.method()
   - Used when subtest count > threshold (for failing tests)

### Thread Safety

TraceLogger maintains per-thread indentation state using ThreadLocal, ensuring correct trace formatting in multi-threaded tests.
