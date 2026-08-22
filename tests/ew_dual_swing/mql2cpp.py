#!/usr/bin/env python3
"""Rough MQL5 -> C++ translator, used only to syntax-check an EA with g++."""
import re, sys

src = open(sys.argv[1]).read()
out = []
TYPES = r'(?:double|int|bool|string|datetime|long|ulong|color|SPivot|SSetup)'

for line in src.split('\n'):
    s = line
    if s.lstrip().startswith('#property'):
        s = '//' + s
    if s.lstrip().startswith('#include'):
        s = '//' + s
    # input group "..."  ->  drop
    if re.match(r'\s*input\s+group\s', s):
        s = '//' + s
    # input <type> name = value;  -> const-ish global
    s = re.sub(r'^\s*input\s+', '', s)
    # local / global dynamic arrays:  double hi[], lo[];  ->  vector
    m = re.match(r'^(\s*)(' + TYPES + r')\s+(\w+\[\](?:\s*,\s*\w+\[\])*)\s*;\s*$', s)
    if m:
        indent, ty, names = m.groups()
        clean = ', '.join(n.strip().replace('[]', '') for n in names.split(','))
        s = f'{indent}std::vector<{ty}> {clean};'
    # array parameters:  Type &name[]  ->  std::vector<Type>& name
    s = re.sub(r'(const\s+)?(' + TYPES + r')\s*&\s*(\w+)\s*\[\s*\]',
               lambda mm: f'{mm.group(1) or ""}std::vector<{mm.group(2)}>& {mm.group(3)}', s)
    # struct reference parameters stay as-is (C++ compatible)
    out.append(s)

body = '\n'.join(out)

# C++ needs prototypes; MQL5 does not. Emit one for every definition.
protos = []
for m in re.finditer(r'^((?:void|bool|int|double|string|datetime|long|ulong|color)\s+\w+\s*\([^()]*\))\s*\n\{', body, re.M):
    protos.append(m.group(1).replace('\n', ' ') + ';')
# OnInit/OnDeinit/OnTick are plain functions in C++ too - fine.
# insert the prototypes just before the first function definition, so the
# structs they reference are already declared
first = None
for m in re.finditer(r'^((?:void|bool|int|double|string|datetime|long|ulong|color)\s+\w+\s*\([^()]*\))\s*\n\{', body, re.M):
    first = m.start()
    break
print('#include "mql_stub.h"')
if first is None:
    print(body)
else:
    print(body[:first])
    print('\n'.join(protos))
    print(body[first:])
