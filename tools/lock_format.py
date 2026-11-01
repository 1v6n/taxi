#!/usr/bin/env python3
"""
lock_format.py

Pre-formatter for SystemVerilog files.
Ensures arguments, parameters, ports, and constraints have proper newlines
and trailing '//' comments so that verible-verilog-format preserves multiline
formatting with clean 4-space indentation and never collapses items into a single line.
"""

import sys
import re
import os

def parse_args_list(inner_str):
    """Parses a comma-separated argument list respecting strings and brackets/parens."""
    clean = re.sub(r'//[^\n]*', '', inner_str)
    args = []
    cur = []
    in_str = False
    p_depth = 0
    b_depth = 0

    for ch in clean:
        if ch == '"' and (not cur or cur[-1] != '\\'):
            in_str = not in_str
            cur.append(ch)
        elif not in_str:
            if ch in '([':
                p_depth += 1
                cur.append(ch)
            elif ch in ')]':
                p_depth -= 1
                cur.append(ch)
            elif ch == '{':
                b_depth += 1
                cur.append(ch)
            elif ch == '}':
                b_depth -= 1
                cur.append(ch)
            elif ch == ',' and p_depth == 0 and b_depth == 0:
                args.append(''.join(cur).strip())
                cur = []
            else:
                cur.append(ch)
        else:
            cur.append(ch)
    if cur:
        tail = ''.join(cur).strip()
        if tail:
            args.append(tail)
    return [a for a in args if a]

def format_system_calls(content):
    """Formats $error, $display, $fatal calls so each argument is on its own line with //."""
    pattern = r'(^[ \t]*\$(?:error|display|fatal|info|warning)\b\s*\()([^;]+?)(\)\s*;)'

    def repl(m):
        prefix = m.group(1).rstrip()
        inner = m.group(2).strip()
        suffix = m.group(3).strip()

        # If already multiline and every non-empty line ends with //, leave indentation to Verible!
        inner_lines = [l.strip() for l in inner.splitlines() if l.strip()]
        if len(inner_lines) > 1 and all(l.endswith('//') for l in inner_lines):
            return m.group(0)

        args = parse_args_list(inner)
        if len(args) > 1 and ('\n' in inner or len(inner) > 60):
            base_indent = len(m.group(1)) - len(m.group(1).lstrip())
            arg_indent = ' ' * (base_indent + 4)
            suff_indent = ' ' * base_indent
            formatted_args = []
            for i, a in enumerate(args):
                clean_a = a.strip()
                comma = ',' if i < len(args) - 1 else ''
                line = f"{arg_indent}{clean_a}{comma}"
                if len(line) + 4 <= 100:
                    line = f"{line}  //"
                formatted_args.append(line)
            return f"{prefix}\n" + "\n".join(formatted_args) + f"\n{suff_indent}{suffix}"
        return m.group(0)

    return re.sub(pattern, repl, content, flags=re.MULTILINE)

def format_signatures(content):
    """Ensures multiline task and function signatures have newline after '(' and '//' on params."""
    pattern = r'(^[ \t]*(?:task|function)\s+(?:automatic\s+)?[^(]+?\()\s*([^;]+?)(\)\s*;)'

    def repl(m):
        prefix = m.group(1).rstrip()
        inner = m.group(2).strip()
        suffix = m.group(3).strip()

        inner_lines = [l.strip() for l in inner.splitlines() if l.strip()]
        if len(inner_lines) >= 1 and all(l.endswith('//') for l in inner_lines):
            return m.group(0)

        if not inner or '\n' not in inner:
            return m.group(0)

        args = parse_args_list(inner)
        if len(args) >= 1:
            base_indent = len(m.group(1)) - len(m.group(1).lstrip())
            arg_indent = ' ' * (base_indent + 4)
            suff_indent = ' ' * base_indent
            formatted_args = []
            for i, a in enumerate(args):
                clean_a = a.strip()
                comma = ',' if i < len(args) - 1 else ''
                line = f"{arg_indent}{clean_a}{comma}"
                if len(line) + 4 <= 100:
                    line = f"{line}  //"
                formatted_args.append(line)
            return f"{prefix}\n" + "\n".join(formatted_args) + f"\n{suff_indent}{suffix}"
        return m.group(0)

    return re.sub(pattern, repl, content, flags=re.MULTILINE)

def format_custom_calls(content):
    """Ensures multiline task calls (e.g. drive_frame, check_frame) have '//'."""
    pattern = r'(^[ \t]*(?:bit\s+\w+\s*=\s*|\w+\s*=\s*)?(?:drive_frame|check_frame|calc_parity|calc_exp_parity)\s*\()([^;]+?)(\)\s*;)'

    def repl(m):
        prefix = m.group(1).rstrip()
        inner = m.group(2).strip()
        suffix = m.group(3).strip()

        inner_lines = [l.strip() for l in inner.splitlines() if l.strip()]
        if len(inner_lines) > 1 and all(l.endswith('//') for l in inner_lines):
            return m.group(0)

        args = parse_args_list(inner)
        if len(args) > 1 and ('\n' in inner or len(inner) > 50):
            base_indent = len(m.group(1)) - len(m.group(1).lstrip())
            arg_indent = ' ' * (base_indent + 4)
            suff_indent = ' ' * base_indent
            formatted_args = []
            for i, a in enumerate(args):
                clean_a = a.strip()
                comma = ',' if i < len(args) - 1 else ''
                line = f"{arg_indent}{clean_a}{comma}"
                if len(line) + 4 <= 100:
                    line = f"{line}  //"
                formatted_args.append(line)
            return f"{prefix}\n" + "\n".join(formatted_args) + f"\n{suff_indent}{suffix}"
        return m.group(0)

    return re.sub(pattern, repl, content, flags=re.MULTILINE)

def format_ports_and_constraints(content):
    """Ensures ports and constraints have trailing '//'."""
    lines = content.splitlines()
    new_lines = []
    in_with = False

    for line in lines:
        stripped = line.strip()
        if 'with {' in line:
            in_with = True

        # Port connection: .name (expr), or .name(expr)
        if re.match(r'^\s*\.[a-zA-Z0-9_$]+\s*\([^)]*\)\s*,?\s*$', line):
            if '//' not in line and '/*' not in line:
                if len(line.rstrip()) + 4 <= 100:
                    line = line.rstrip() + '  //'

        # Constraints inside with { ... }
        elif in_with and stripped.endswith(';'):
            if '//' not in line and '/*' not in line:
                if len(line.rstrip()) + 4 <= 100:
                    line = line.rstrip() + '  //'

        if in_with and '}' in line:
            in_with = False

        new_lines.append(line)

    return '\n'.join(new_lines) + ('\n' if content.endswith('\n') else '')

def process_file(filepath):
    """Processes a single SystemVerilog file in-place."""
    if not os.path.isfile(filepath):
        return

    with open(filepath, 'r', encoding='utf-8') as f:
        original = f.read()

    modified = format_signatures(original)
    modified = format_system_calls(modified)
    modified = format_custom_calls(modified)
    modified = format_ports_and_constraints(modified)

    if modified != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(modified)
        print(f"[lock_format] Formatted & locked: {filepath}")

def main():
    if len(sys.argv) < 2:
        print("Usage: lock_format.py <file1.sv> [file2.sv ...]")
        sys.exit(0)

    for filepath in sys.argv[1:]:
        process_file(filepath)

if __name__ == '__main__':
    main()
