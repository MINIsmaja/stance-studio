# Relaxed jbeam reader and default-tree helpers for the offline audits.
# jbeam is JSON with comments, optional commas and trailing commas.
import json, os, re, zipfile

TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|[A-Za-z_][A-Za-z0-9_]*|[\[\]{}:,]|\S')


def relaxed(t):
    # tokenize, then put a comma wherever two values touch (never inside strings)
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    out = []
    for line in t.split('\n'):
        # strip // comments outside strings
        i, n, buf = 0, len(line), []
        while i < n:
            c = line[i]
            if c == '"':
                j = i + 1
                while j < n and line[j] != '"':
                    j += 2 if line[j] == '\\' else 1
                buf.append(line[i:j + 1]); i = j + 1
            elif line.startswith('//', i):
                break
            else:
                buf.append(c); i += 1
        out.append(''.join(buf))
    toks = TOKEN.findall('\n'.join(out))
    res = []
    def is_end(x): return x[0] == '"' or x in (']', '}') or x[0].isdigit() or x[0] in '-+.' or x[0].isalpha()
    def is_start(x): return x[0] == '"' or x in ('[', '{') or x[0].isdigit() or x[0] in '-+.' or x[0].isalpha()
    for tok in toks:
        if tok[0] == '+' and len(tok) > 1:
            tok = tok[1:]
        if tok in ('NaN', 'nan'):
            tok = 'null'
        if tok[0].isdigit() or (tok[0] in '-.' and len(tok) > 1):
            if tok.endswith('.'): tok += '0'
            if tok.startswith('.'): tok = '0' + tok
            if tok.startswith('-.'): tok = '-0' + tok[1:]
        if res:
            prev = res[-1]
            if is_end(prev) and is_start(tok):
                res.append(',')
            elif prev == ',' and tok in (']', '}', ','):
                res.pop()
                if tok == ',':
                    continue
        res.append(tok)
    return json.loads(' '.join(res))


def load_zip(path, parts):
    """Adds every part of every .jbeam in the zip to parts (first one wins); returns unreadable file count."""
    z = zipfile.ZipFile(path)
    bad = 0
    for name in z.namelist():
        if not name.endswith('.jbeam'):
            continue
        try:
            d = relaxed(z.read(name).decode('utf-8', 'replace'))
        except Exception:
            bad += 1
            continue
        if isinstance(d, dict):
            for k, v in d.items():
                if isinstance(v, dict):
                    parts.setdefault(k, v)
    return bad


def slot_rows(part):
    rows = part.get('slots2') or part.get('slots')
    if not isinstance(rows, list) or not rows or not isinstance(rows[0], list):
        return []
    h = rows[0]
    def col(x): return h.index(x) if x in h else None
    ni, ti, di, de, ai = col('name'), col('type'), col('default'), col('description'), col('allowTypes')
    res = []
    for r in rows[1:]:
        if not isinstance(r, list):
            continue
        sid = r[ni] if ni is not None and ni < len(r) else (r[ti] if ti is not None and ti < len(r) else None)
        if not isinstance(sid, str):
            continue
        allow = r[ai] if ai is not None and ai < len(r) and isinstance(r[ai], list) else [r[ti]] if ti is not None and ti < len(r) else [sid]
        res.append({'id': sid, 'allow': allow,
                    'default': r[di] if di is not None and di < len(r) and isinstance(r[di], str) else '',
                    'desc': r[de] if de is not None and de < len(r) and isinstance(r[de], str) else sid})
    return res


def vehicle_parts(game, car):
    """All parts a vehicle can use (common.zip + its own zip) and the name of its main part."""
    parts, carparts = {}, {}
    load_zip(os.path.join(game, 'content/vehicles/common.zip'), parts)
    load_zip(os.path.join(game, 'content/vehicles', car + '.zip'), carparts)
    parts.update(carparts)
    main = next((n for n, p in carparts.items() if p.get('slotType') == 'main'), None)
    return parts, main


def default_parts(parts, main, max_depth=14):
    """Names of the parts in the default tree, parents first."""
    order, seen = [], set()
    def walk(name, depth):
        if name in seen or depth > max_depth or name not in parts:
            return
        seen.add(name); order.append(name)
        for r in slot_rows(parts[name]):
            if r['default'] and r['default'] in parts:
                walk(r['default'], depth + 1)
    if main:
        walk(main, 0)
    return order
