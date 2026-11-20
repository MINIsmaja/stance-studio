# Wheel meshes Stance Studio would leave behind (or move twice) when it moves a wheel, per vehicle,
# on the default parts. It emulates stance.lua's mesh pick for every wheel row:
#   old rule: every group of the mesh is one of the wheel's groups
#   new rule: wheels that share axle nodes (duals) count as one wheel with all their groups, and
#             groups that no node and no wheel row uses are ignored (the mesh still needs one of
#             the wheel's own groups)
# A wheel's groups are its row's group / hubGroup / hubcapGroup plus the groups of its axle nodes.
# Meshes are checked for the default parts and for every part that fits a slot of the default tree
# (other wheels, tires, hubs), with the default nodes and wheel rows.
# Usage: python3 -I audit_wheel_meshes.py <game dir> car...   (no cars = every vehicle with wheels)
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jbeam_parse import load_zip, slot_rows

SECTIONS = ('pressureWheels', 'wheels', 'hubWheels', 'monoHubWheels', 'hubWheelsTSV', 'hubWheelsTSI')


def glist(g):
    if isinstance(g, str): return [g] if g else []
    if isinstance(g, list): return [x for x in g if isinstance(x, str) and x]
    return []


def collect(parts, main):
    nodeGroup, rows, flex, seen = {}, [], [], set()
    allow = set()
    def walk(name, depth):
        if name in seen or depth > 14 or name not in parts: return
        seen.add(name); p = parts[name]
        r = p.get('nodes')
        if isinstance(r, list) and r and isinstance(r[0], list):
            g = []
            for x in r[1:]:
                if isinstance(x, dict) and 'group' in x: g = glist(x['group'])
                elif isinstance(x, list) and x and isinstance(x[0], str):
                    gg = g
                    for y in x[1:]:
                        if isinstance(y, dict) and 'group' in y: gg = glist(y['group'])
                    nodeGroup[x[0]] = gg
        for sec in SECTIONS:
            r = p.get(sec)
            if not isinstance(r, list) or not r or not isinstance(r[0], list): continue
            h = r[0]
            def col(n): return next((i for i, v in enumerate(h) if isinstance(v, str) and v.rstrip(':') == n), None)
            ci = {k: col(k) for k in ('name', 'hubGroup', 'group', 'node1', 'node2')}
            opts = {}
            for x in r[1:]:
                if isinstance(x, dict): opts.update(x)
                elif isinstance(x, list):
                    row = dict(opts)
                    for k, i in ci.items():
                        if i is not None and i < len(x): row[k] = x[i]
                    for y in x:
                        if isinstance(y, dict): row.update(y)
                    if row.get('numRays') == 0: continue
                    rows.append(row)
        r = p.get('flexbodies')
        if isinstance(r, list):
            for x in r[1:]:
                if isinstance(x, list) and len(x) > 1 and isinstance(x[0], str):
                    flex.append((x[0], glist(x[1]), name))
        for s in slot_rows(p):
            allow.update(a for a in s['allow'] if isinstance(a, str))
            if s['default'] and s['default'] in parts: walk(s['default'], depth + 1)
    walk(main, 0)
    # every other part that fits a slot of the default tree, and the parts that fit their slots,
    # and so on: their meshes only (nodes and wheel rows stay the default ones)
    def fits(p):
        st = p.get('slotType')
        return any(isinstance(x, str) and x in allow for x in (st if isinstance(st, list) else [st]))
    extra, grew = set(), True
    while grew:
        grew = False
        for name, p in parts.items():
            if name in seen or name in extra or not fits(p): continue
            extra.add(name); grew = True
            for s in slot_rows(p):
                allow.update(a for a in s['allow'] if isinstance(a, str))
    for name in sorted(extra):
        r = parts[name].get('flexbodies')
        if isinstance(r, list):
            for x in r[1:]:
                if isinstance(x, list) and len(x) > 1 and isinstance(x[0], str):
                    flex.append((x[0], glist(x[1]), name))
    return nodeGroup, rows, flex


def audit(nodeGroup, rows, flex):
    used = set(g for gs in nodeGroup.values() for g in gs)
    for row in rows:
        for k in ('group', 'hubGroup', 'hubcapGroup'):
            used.update(glist(row.get(k)))
    rowSets = []
    for row in rows:
        s = set(glist(row.get('group'))) | set(glist(row.get('hubGroup'))) | set(glist(row.get('hubcapGroup')))
        for n in (row.get('node1'), row.get('node2')):
            s |= set(nodeGroup.get(n, []))
        rowSets.append((str(row.get('name')), s))
    wheelish = set().union(*[s for _, s in rowSets]) if rowSets else set()
    # duals: rows sharing an axle node are one unit
    unit = list(range(len(rows)))
    def find(i):
        while unit[i] != i: i = unit[i]
        return i
    for i in range(len(rows)):
        for j in range(i):
            a = {rows[i].get('node1'), rows[i].get('node2')} - {None}
            b = {rows[j].get('node1'), rows[j].get('node2')} - {None}
            if a & b: unit[find(i)] = find(j)
    unitSets = {}
    for i, (n, s) in enumerate(rowSets):
        u = find(i)
        name, old = unitSets.get(u, ('', set()))
        unitSets[u] = ((name + '+' if name else '') + n, old | s)
    old_miss, new_miss, multi = [], [], []
    seen = set()
    for mesh, gs, part in flex:
        if (mesh, tuple(gs)) in seen: continue
        seen.add((mesh, tuple(gs)))
        if not gs or not (set(gs) & wheelish): continue
        # only real wheel meshes: every group it uses belongs to one wheel (or dual pair). Meshes
        # that also hang on the knuckle or axle (calipers, half-shafts) are meant to stretch.
        usedGs = [g for g in gs if g in used]
        if not any(all(g in s for g in usedGs) for _, s in unitSets.values()): continue
        old = [n for n, s in rowSets if all(g in s for g in gs)]
        new = [n for n, s in unitSets.values() if any(g in s for g in gs) and all(g in s or g not in used for g in gs)]
        if not old: old_miss.append(f'{mesh} {gs}')
        if not new: new_miss.append(f'{mesh} {gs}')
        if len(set(new)) > 1: multi.append(f'{mesh} {gs} -> {sorted(set(new))}')
    return old_miss, new_miss, multi


def main():
    game, cars = sys.argv[1], sys.argv[2:]
    vdir = os.path.join(game, 'content/vehicles')
    common = {}
    load_zip(os.path.join(vdir, 'common.zip'), common)
    if not cars:
        cars = sorted(f[:-4] for f in os.listdir(vdir) if f.endswith('.zip') and f != 'common.zip')
    tot_old = tot_new = 0
    for car in cars:
        parts, carparts = dict(common), {}
        try:
            load_zip(os.path.join(vdir, car + '.zip'), carparts)
        except Exception as e:
            print(f'{car:14s} unreadable: {e}'); continue
        parts.update(carparts)
        main_part = next((n for n, p in carparts.items() if p.get('slotType') == 'main'), None)
        if not main_part: continue
        nodeGroup, rows, flex = collect(parts, main_part)
        if not rows: continue
        old_miss, new_miss, multi = audit(nodeGroup, rows, flex)
        tot_old += len(old_miss); tot_new += len(new_miss)
        print(f'{car:14s} {len(rows):2d} wheels  left behind: now {len(old_miss):2d}, fixed {len(new_miss):2d}   claimed by 2+ wheels: {len(multi)}')
        for b in old_miss[:5]: print('     left behind now :', b)
        for b in new_miss[:5]: print('     STILL left behind:', b)
        for b in multi[:3]: print('     2+ wheels       :', b)
    print(f'total wheel meshes left behind: now {tot_old}, with the fix {tot_new}')


main()
