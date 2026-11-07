#!/usr/bin/env python3
"""Structural sanity check for Lua sources, for machines with no Lua runtime.

This is NOT a Lua parser and does not execute anything. It tokenizes Lua
(strings, long strings, comments, numbers, names, operators) and checks:
  * block keywords balance: function/if/do/for/while/repeat vs end/until
  * (), {}, [] balance, and that blocks close at the bracket depth they opened
  * operators from other languages that are syntax errors in Lua
    (!=, +=, -=, *=, /=, ++, &&, ||)
  * unterminated strings / long strings / long comments

Usage: python3 -I tests/tools/lua_structure_check.py FILE.lua [...]
Exit status 0 when every file passes, 1 otherwise.
"""
import re
import sys

LONG_OPEN = re.compile(r'\[(=*)\[')
NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
NUMBER = re.compile(r'0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')
BAD_OPS = ['!=', '+=', '-=', '*=', '/=', '++', '&&', '||']
OPS = ['...', '..', '==', '~=', '<=', '>=', '::', '//', '<<', '>>']


def tokenize(src):
    """Yields (kind, text, line)."""
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
        elif c in ' \t\r':
            i += 1
        elif src.startswith('--', i):
            m = LONG_OPEN.match(src, i + 2)
            if m:
                close = ']' + m.group(1) + ']'
                j = src.find(close, m.end())
                if j < 0:
                    raise SyntaxError(f'line {line}: unterminated long comment')
                line += src.count('\n', i, j)
                i = j + len(close)
            else:
                j = src.find('\n', i)
                i = n if j < 0 else j
        elif c in '"\'':
            j, start = i + 1, line
            while True:
                if j >= n or src[j] == '\n':
                    raise SyntaxError(f'line {start}: unterminated string')
                if src[j] == '\\':
                    if j + 1 < n and src[j + 1] == '\n':
                        line += 1
                    j += 2
                    continue
                if src[j] == c:
                    break
                j += 1
            yield ('string', src[i:j + 1], start)
            i = j + 1
        elif c == '[' and LONG_OPEN.match(src, i):
            m = LONG_OPEN.match(src, i)
            close = ']' + m.group(1) + ']'
            j = src.find(close, m.end())
            if j < 0:
                raise SyntaxError(f'line {line}: unterminated long string')
            yield ('string', src[i:j + len(close)], line)
            line += src.count('\n', i, j)
            i = j + len(close)
        elif c.isdigit() or (c == '.' and i + 1 < n and src[i + 1].isdigit()):
            m = NUMBER.match(src, i)
            yield ('number', m.group(0), line)
            i = m.end()
        elif c.isalpha() or c == '_':
            m = NAME.match(src, i)
            yield ('name', m.group(0), line)
            i = m.end()
        else:
            for op in BAD_OPS:
                if src.startswith(op, i):
                    raise SyntaxError(f'line {line}: "{op}" is not a Lua operator')
            for op in OPS:
                if src.startswith(op, i):
                    yield ('op', op, line)
                    i += len(op)
                    break
            else:
                yield ('op', c, line)
                i += 1


def check(src):
    blocks = []      # (keyword, line, bracket depth)
    brackets = []    # (char, line)
    pending_do = 0   # 'for'/'while' headers waiting for their 'do'
    pairs = {')': '(', '}': '{', ']': '['}
    prev = None
    for kind, text, line in tokenize(src):
        if kind == 'op':
            if text in '({[':
                brackets.append((text, line))
            elif text in ')}]':
                if not brackets or brackets[-1][0] != pairs[text]:
                    raise SyntaxError(f'line {line}: unbalanced "{text}"')
                brackets.pop()
        elif kind == 'name' and prev != '.' and prev != ':':
            depth = len(brackets)
            if text in ('function', 'if', 'repeat'):
                blocks.append((text, line, depth))
            elif text in ('for', 'while'):
                blocks.append((text, line, depth))
                pending_do += 1
            elif text == 'do':
                if pending_do:
                    pending_do -= 1
                else:
                    blocks.append(('do', line, depth))
            elif text in ('end', 'until'):
                if not blocks:
                    raise SyntaxError(f'line {line}: "{text}" without an open block')
                kw, opened, odepth = blocks.pop()
                if (text == 'until') != (kw == 'repeat'):
                    raise SyntaxError(f'line {line}: "{text}" closes "{kw}" from line {opened}')
                if odepth != depth:
                    raise SyntaxError(f'line {line}: "{text}" closes "{kw}" from line {opened} '
                                      f'inside an unclosed bracket')
        prev = text if kind == 'op' else None
    if brackets:
        ch, line = brackets[-1]
        raise SyntaxError(f'line {line}: unclosed "{ch}"')
    if blocks:
        kw, line, _ = blocks[-1]
        raise SyntaxError(f'line {line}: "{kw}" is never closed')
    if pending_do:
        raise SyntaxError('a for/while header has no "do"')


def main(paths):
    bad = 0
    for path in paths:
        with open(path, encoding='utf-8') as f:
            src = f.read()
        try:
            check(src)
        except SyntaxError as e:
            bad += 1
            print(f'FAIL {path}: {e.msg if hasattr(e, "msg") else e}')
        else:
            print(f'ok   {path}')
    print(f'\n{len(paths) - bad} ok, {bad} failed (structural check only, not a Lua run)')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
