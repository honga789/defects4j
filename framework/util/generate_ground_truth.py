#!/usr/bin/env python3
"""
Generate ground-truth.json for a Defects4J bug.

This script extracts metadata about a bug including:
- Modified files and classes
- Modified methods (by diffing buggy and fixed versions)
- Trigger tests
- Commit information

Usage:
    python generate_ground_truth.py -p Math -b 1 --buggy-dir /path/to/buggy --fixed-dir /path/to/fixed -o output.json
"""

import subprocess
import json
import argparse
import os
import re
import sys
from datetime import datetime
from pathlib import Path


def run_cmd(cmd, cwd=None):
    """Run a command and return stdout."""
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, cwd=cwd
    )
    return result.stdout.strip(), result.returncode


def get_defects4j_export(property_name, work_dir):
    """Get a property from defects4j export."""
    stdout, _ = run_cmd(f"defects4j export -p {property_name}", cwd=work_dir)
    return stdout.strip().split('\n') if stdout.strip() else []


def get_defects4j_query(project, bug_id, query_fields):
    """Query defects4j for bug metadata."""
    fields = ','.join(query_fields)
    stdout, _ = run_cmd(f"defects4j query -p {project} -q '{fields}'")
    
    result = {}
    for line in stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split(',')
        if len(parts) >= 1:
            bid = parts[0]
            if bid == str(bug_id):
                for i, field in enumerate(query_fields):
                    if i < len(parts):
                        result[field] = parts[i]
                break
    return result


def find_java_files(directory, classes):
    """Find Java source files for given class names."""
    files = {}
    for cls in classes:
        # Convert class name to file path
        path = cls.replace('.', '/') + '.java'
        for root, dirs, filenames in os.walk(directory):
            for filename in filenames:
                if filename.endswith('.java'):
                    full_path = os.path.join(root, filename)
                    rel_path = os.path.relpath(full_path, directory)
                    if rel_path.endswith(path):
                        files[cls] = rel_path
                        break
    return files


def extract_method_from_diff_header(line):
    """Extract method signature from git diff hunk header."""
    # Format: @@ -line,count +line,count @@ methodSignature
    match = re.search(r'@@.*@@\s*(.+)$', line)
    if match:
        method_sig = match.group(1).strip()
        # Clean up common patterns
        method_sig = re.sub(r'\s+', ' ', method_sig)
        return method_sig
    return None


def parse_java_method_at_line(file_path, line_number):
    """Parse Java file to find method containing the given line."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except:
        return None
    
    # Simple heuristic: find the method declaration before this line
    method_pattern = re.compile(
        r'(public|private|protected|static|\s)*\s+' +
        r'[\w<>\[\],\s]+\s+' +  # return type
        r'(\w+)\s*\([^)]*\)'     # method name and params
    )
    
    constructor_pattern = re.compile(
        r'(public|private|protected|\s)*\s*' +
        r'(\w+)\s*\([^)]*\)\s*(throws\s+[\w,\s]+)?\s*\{'
    )
    
    current_method = None
    brace_count = 0
    in_method = False
    
    for i, line in enumerate(lines):
        # Check for method declaration
        for pattern in [method_pattern, constructor_pattern]:
            match = pattern.search(line)
            if match:
                method_name = match.group(2) if len(match.groups()) >= 2 else match.group(1)
                if method_name and method_name not in ['if', 'while', 'for', 'switch', 'catch']:
                    current_method = {
                        'name': method_name,
                        'line': i + 1,
                        'signature': line.strip()
                    }
        
        # Track braces to know when we exit a method
        brace_count += line.count('{') - line.count('}')
        
        if i + 1 == line_number and current_method:
            return current_method
    
    return current_method


def find_method_at_line(file_path, target_line):
    """Find the method that contains a specific line number using a more robust approach."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            lines = content.split('\n')
    except:
        return None
    
    # Track method boundaries
    method_stack = []
    brace_depth = 0
    
    # Join lines to handle multi-line declarations
    i = 0
    while i < len(lines):
        line = lines[i]
        line_num = i + 1
        
        # Track braces - count only outside strings
        open_braces = line.count('{')
        close_braces = line.count('}')
        
        # Check for method/constructor declaration
        # Handle both single-line and multi-line declarations
        stripped = line.strip()
        
        # Look for method declaration patterns
        # Pattern: visibility? modifiers? returnType? methodName(params) throws? {
        is_method_decl = False
        method_name = None
        params = ''
        
        # Check if this line starts a method (has opening parenthesis)
        if '(' in stripped and not stripped.startswith('//') and not stripped.startswith('*'):
            # Extract potential method name before (
            before_paren = stripped.split('(')[0].strip()
            tokens = before_paren.split()
            
            if tokens:
                potential_name = tokens[-1]
                # Skip control structures
                if potential_name not in ['if', 'while', 'for', 'switch', 'catch', 'try', 'synchronized', 'return', 'new']:
                    # Check if this looks like a method declaration
                    # Should have either public/private/protected or be preceded by a type
                    if (any(mod in stripped for mod in ['public', 'private', 'protected', 'void', 'static']) or 
                        (len(tokens) >= 2 and potential_name[0].isupper() == False)):  # method names start lowercase typically
                        
                        # Find the full declaration including params
                        full_decl = stripped
                        temp_i = i
                        
                        # Handle multi-line declarations
                        while ')' not in full_decl and temp_i < len(lines) - 1:
                            temp_i += 1
                            full_decl += ' ' + lines[temp_i].strip()
                        
                        # Extract params
                        try:
                            paren_start = full_decl.index('(')
                            paren_end = full_decl.index(')', paren_start)
                            params_raw = full_decl[paren_start + 1:paren_end]
                            
                            # Has opening brace (either on same line or later)?
                            has_brace = '{' in full_decl or any('{' in lines[j] for j in range(i, min(temp_i + 3, len(lines))))
                            
                            # Not an assignment or method call
                            is_call = '=' in full_decl.split('(')[0] or ';' in full_decl.split('{')[0] if '{' in full_decl else ';' in full_decl
                            
                            if has_brace and not is_call:
                                is_method_decl = True
                                method_name = potential_name
                                
                                # Format params - extract types only
                                param_types = []
                                for param in params_raw.split(','):
                                    param = param.strip()
                                    if param:
                                        # Handle generic types
                                        param = re.sub(r'<[^>]+>', '', param)
                                        parts = param.split()
                                        if len(parts) >= 2:
                                            param_type = parts[-2]
                                        elif len(parts) == 1:
                                            param_type = parts[0]
                                        else:
                                            continue
                                        # Simplify type name
                                        param_type = param_type.split('.')[-1]
                                        param_types.append(param_type)
                                
                                params = ','.join(param_types)
                        except (ValueError, IndexError):
                            pass
        
        if is_method_decl and method_name:
            method_sig = f"{method_name}({params})"
            method_stack.append({
                'name': method_name,
                'signature': method_sig,
                'start_line': line_num,
                'brace_depth_at_start': brace_depth + open_braces
            })
        
        # Update brace depth
        brace_depth += open_braces - close_braces
        
        # Check if we've exited any methods
        while method_stack and brace_depth < method_stack[-1]['brace_depth_at_start']:
            completed_method = method_stack.pop()
            completed_method['end_line'] = line_num
            
            if completed_method['start_line'] <= target_line <= line_num:
                return completed_method
        
        # Check if target line is in current method
        if method_stack and line_num == target_line:
            return method_stack[-1]
        
        i += 1
    
    # Check remaining methods on stack
    if method_stack:
        for method in method_stack:
            if method['start_line'] <= target_line:
                return method
    
    return None


def find_method_by_name(file_path, method_name):
    """Find a method by name in a file and return its start line."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            lines = content.split('\n')
    except:
        return None
    
    # Build multi-line buffer to handle declarations across lines
    in_comment = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Track block comments
        if '/*' in stripped and '*/' not in stripped:
            in_comment = True
            continue
        if '*/' in stripped:
            in_comment = False
            continue
        
        # Skip line comments and inside block comments
        if in_comment or stripped.startswith('//') or stripped.startswith('*'):
            continue
        
        # Look for method/constructor declaration pattern
        # Format: [modifiers] [returnType] methodName(
        # For constructor, the class name matches method name
        if method_name + '(' in stripped or method_name + ' (' in stripped:
            # Get the part before the method name
            before_idx = stripped.find(method_name)
            before = stripped[:before_idx].strip()
            
            # Check for method declaration indicators
            # Should have modifiers or be at start of declaration
            is_decl = False
            
            # Check for typical method declaration patterns
            if any(mod in before for mod in ['public', 'private', 'protected', 'static', 'final', 'synchronized', 'abstract']):
                is_decl = True
            # Constructor: line starts with class name (after optional modifiers)
            elif before == '' or before.endswith(' ') and not before.endswith('.'):
                # Check if it has opening paren and looks like a declaration
                after_name = stripped[before_idx + len(method_name):]
                if after_name.startswith('('):
                    # Make sure it's not a method call (no preceding . or =)
                    if not before.rstrip().endswith('.') and not before.rstrip().endswith('='):
                        is_decl = True
            
            if is_decl:
                # Check that it has opening brace (could be on same line or next lines)
                combined = stripped
                j = i + 1
                while '{' not in combined and j < min(i + 5, len(lines)):
                    combined += ' ' + lines[j].strip()
                    j += 1
                
                if '{' in combined or 'throws' in combined:
                    return {
                        'name': method_name,
                        'start_line': i + 1
                    }
    
    return None


def find_method_by_signature(file_path, method_name, signature):
    """Find a method by name and signature (parameter count/types) in a file."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            lines = content.split('\n')
    except:
        return None
    
    # Extract param count from signature like "BigFraction(double,double,int,int)"
    sig_params = signature.split('(')[1].rstrip(')').split(',') if '(' in signature else []
    sig_param_count = len([p for p in sig_params if p.strip()])
    
    in_comment = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Track block comments
        if '/*' in stripped and '*/' not in stripped:
            in_comment = True
            continue
        if '*/' in stripped:
            in_comment = False
            continue
        
        # Skip line comments and inside block comments
        if in_comment or stripped.startswith('//') or stripped.startswith('*'):
            continue
        
        # Look for method/constructor declaration pattern
        if method_name + '(' in stripped or method_name + ' (' in stripped:
            before_idx = stripped.find(method_name)
            before = stripped[:before_idx].strip()
            
            is_decl = False
            if any(mod in before for mod in ['public', 'private', 'protected', 'static', 'final', 'synchronized', 'abstract']):
                is_decl = True
            elif before == '' or (before.endswith(' ') and not before.endswith('.')):
                after_name = stripped[before_idx + len(method_name):]
                if after_name.startswith('('):
                    if not before.rstrip().endswith('.') and not before.rstrip().endswith('='):
                        is_decl = True
            
            if is_decl:
                # Get full declaration to count params
                combined = stripped
                j = i + 1
                while ')' not in combined and j < min(i + 10, len(lines)):
                    combined += ' ' + lines[j].strip()
                    j += 1
                
                # Extract params from this declaration
                try:
                    paren_start = combined.index(method_name) + len(method_name)
                    paren_start = combined.index('(', paren_start)
                    paren_end = combined.index(')', paren_start)
                    params_str = combined[paren_start + 1:paren_end]
                    
                    # Count non-empty params
                    params = [p.strip() for p in params_str.split(',') if p.strip()]
                    param_count = len(params)
                    
                    # Match if param count is same
                    if param_count == sig_param_count:
                        return {
                            'name': method_name,
                            'start_line': i + 1
                        }
                except (ValueError, IndexError):
                    pass
    
    return None


def extract_modified_methods(buggy_dir, fixed_dir, modified_classes, src_dir):
    """Extract modified methods by comparing buggy and fixed versions."""
    modified_methods = []
    
    for cls in modified_classes:
        if not cls:
            continue
            
        # Convert class name to file path
        file_path = cls.replace('.', '/') + '.java'
        buggy_file = os.path.join(buggy_dir, src_dir, file_path)
        fixed_file = os.path.join(fixed_dir, src_dir, file_path)
        
        if not os.path.exists(buggy_file) or not os.path.exists(fixed_file):
            # Try to find the file by searching
            buggy_file = None
            fixed_file = None
            target_filename = cls.split('.')[-1] + '.java'
            target_path_part = cls.replace('.', '/')
            
            for root, dirs, files in os.walk(buggy_dir):
                for f in files:
                    if f == target_filename:
                        full_path = os.path.join(root, f)
                        if target_path_part in full_path.replace('\\', '/'):
                            buggy_file = full_path
                            break
                if buggy_file:
                    break
                    
            for root, dirs, files in os.walk(fixed_dir):
                for f in files:
                    if f == target_filename:
                        full_path = os.path.join(root, f)
                        if target_path_part in full_path.replace('\\', '/'):
                            fixed_file = full_path
                            break
                if fixed_file:
                    break
            
            if not buggy_file or not fixed_file:
                print(f"Warning: Could not find files for class {cls}")
                continue
        
        # Get diff between files with context
        diff_cmd = f'diff -U3 "{buggy_file}" "{fixed_file}"'
        diff_output, _ = run_cmd(diff_cmd)
        
        if not diff_output:
            continue
        
        # Parse diff to find changed line numbers
        changed_lines_buggy = set()
        changed_lines_fixed = set()
        
        current_buggy_line = 0
        current_fixed_line = 0
        
        for line in diff_output.split('\n'):
            if line.startswith('@@'):
                # Parse hunk header: @@ -start,count +start,count @@
                match = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', line)
                if match:
                    current_buggy_line = int(match.group(1))
                    current_fixed_line = int(match.group(3))
            elif line.startswith('-') and not line.startswith('---'):
                changed_lines_buggy.add(current_buggy_line)
                current_buggy_line += 1
            elif line.startswith('+') and not line.startswith('+++'):
                changed_lines_fixed.add(current_fixed_line)
                current_fixed_line += 1
            elif not line.startswith('\\'):  # Not "\ No newline at end of file"
                current_buggy_line += 1
                current_fixed_line += 1
        
        # Find methods for each changed line
        methods_found = {}
        
        for line_num in changed_lines_fixed:
            method_info = find_method_at_line(fixed_file, line_num)
            if method_info:
                method_key = method_info['signature']
                if method_key not in methods_found:
                    methods_found[method_key] = {
                        'file': file_path,
                        'class': cls,
                        'method': method_info['signature'],
                        'method_name': method_info['name'],
                        'line_start_buggy': None,
                        'line_start_fixed': method_info.get('start_line')
                    }
                # Update line_start_fixed if we found a smaller one
                if methods_found[method_key]['line_start_fixed'] is None:
                    methods_found[method_key]['line_start_fixed'] = method_info.get('start_line')
        
        # Also check buggy file for the same methods and get their line_start
        for line_num in changed_lines_buggy:
            method_info = find_method_at_line(buggy_file, line_num)
            if method_info:
                method_key = method_info['signature']
                if method_key not in methods_found:
                    methods_found[method_key] = {
                        'file': file_path,
                        'class': cls,
                        'method': method_info['signature'],
                        'method_name': method_info['name'],
                        'line_start_buggy': method_info.get('start_line'),
                        'line_start_fixed': None
                    }
                else:
                    # Update line_start_buggy
                    if methods_found[method_key]['line_start_buggy'] is None:
                        methods_found[method_key]['line_start_buggy'] = method_info.get('start_line')
        
        # For methods found only in fixed, try to find them in buggy too
        for method_key, method_data in methods_found.items():
            if method_data['line_start_buggy'] is None:
                # Search for the method in buggy file by signature
                buggy_method = find_method_by_signature(buggy_file, method_data['method_name'], method_data['method'])
                if buggy_method:
                    method_data['line_start_buggy'] = buggy_method.get('start_line')
            if method_data['line_start_fixed'] is None:
                # Search for the method in fixed file by signature
                fixed_method = find_method_by_signature(fixed_file, method_data['method_name'], method_data['method'])
                if fixed_method:
                    method_data['line_start_fixed'] = fixed_method.get('start_line')
        
        # Add found methods to result
        for method_data in methods_found.values():
            modified_methods.append(method_data)
    
    return modified_methods


def main():
    parser = argparse.ArgumentParser(description='Generate ground-truth.json for a Defects4J bug')
    parser.add_argument('-p', '--project', required=True, help='Project ID (e.g., Math)')
    parser.add_argument('-b', '--bug', required=True, type=int, help='Bug ID')
    parser.add_argument('--buggy-dir', required=True, help='Path to buggy version')
    parser.add_argument('--fixed-dir', required=True, help='Path to fixed version')
    parser.add_argument('-o', '--output', required=True, help='Output JSON file')
    
    args = parser.parse_args()
    
    print(f"Generating ground truth for {args.project}-{args.bug}...")
    
    # Get metadata from defects4j
    query_result = get_defects4j_query(args.project, args.bug, [
        'bug.id', 'revision.id.buggy', 'revision.id.fixed', 'report.id', 'report.url'
    ])
    
    # Get modified classes
    modified_classes = get_defects4j_export('classes.modified', args.buggy_dir)
    modified_classes = [c for c in modified_classes if c]
    
    # Get trigger tests
    trigger_tests = get_defects4j_export('tests.trigger', args.buggy_dir)
    trigger_tests = [t for t in trigger_tests if t]
    
    # Get source directory
    src_dirs = get_defects4j_export('dir.src.classes', args.buggy_dir)
    src_dir = src_dirs[0] if src_dirs else 'src/main/java'
    
    # Get test directory
    test_dirs = get_defects4j_export('dir.src.tests', args.buggy_dir)
    test_dir = test_dirs[0] if test_dirs else 'src/test/java'
    
    # Extract modified methods
    print("Extracting modified methods...")
    modified_methods = extract_modified_methods(
        args.buggy_dir, args.fixed_dir, modified_classes, src_dir
    )
    
    # Build function list (fully qualified method names)
    functions = []
    for m in modified_methods:
        func_name = f"{m['class']}::{m['method']}"
        if func_name not in functions:
            functions.append(func_name)
    
    # Get test class names from trigger tests
    test_classes = list(set([t.split('::')[0] for t in trigger_tests if '::' in t]))
    
    # Convert class names to file paths
    src_files = [cls.replace('.', '/') + '.java' for cls in modified_classes]
    test_files = [cls.replace('.', '/') + '.java' for cls in test_classes]
    
    # Build ground truth JSON
    ground_truth = {
        "version": f"{args.project}-{args.bug}",
        "project_id": args.project,
        "bug_id": args.bug,
        
        "files": {
            "src": src_files,
            "test": test_files
        },
        
        "classes": {
            "modified": modified_classes,
            "test": test_classes
        },
        
        "functions": functions,
        
        "modified_locations": modified_methods,
        
        "commit_buggy": query_result.get('revision.id.buggy', ''),
        "commit_fixed": query_result.get('revision.id.fixed', ''),
        
        "report_id": query_result.get('report.id', ''),
        "report_url": query_result.get('report.url', ''),
        
        "tests_trigger": trigger_tests,
        
        "source_dir": src_dir,
        "test_dir": test_dir,
        
        "timing": {
            "generated_at": datetime.now().isoformat()
        }
    }
    
    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(ground_truth, f, indent=4, ensure_ascii=False)
    
    print(f"Ground truth written to: {args.output}")
    print(f"  - Modified classes: {len(modified_classes)}")
    print(f"  - Modified methods: {len(functions)}")
    print(f"  - Trigger tests: {len(trigger_tests)}")
    
    # Print summary of modified methods
    if functions:
        print("\nModified functions:")
        for func in functions:
            print(f"  - {func}")


if __name__ == '__main__':
    main()
