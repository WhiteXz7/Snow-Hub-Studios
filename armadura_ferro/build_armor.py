#!/usr/bin/env python3
"""Medieval iron cuirass + spaulders for Roblox R6 (torso-local space)."""

from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "capacete_romano"))

from build_helmet import (  # noqa: E402
    GOLD,
    GOLD_D,
    LEATHER_C,
    LINER,
    Mesh,
    add_shell_indexed,
    export_obj,
    grid_surface,
    lerp,
    render,
    tube,
    uv_sphere,
    vnorm,
    write_lua_quantized,
)

IRON = np.array([0.42, 0.44, 0.47])
IRON_D = np.array([0.22, 0.23, 0.25])
IRON_H = np.array([0.62, 0.64, 0.68])
STRAP = np.array([0.12, 0.08, 0.05])


def load_tex(name):
    p = os.path.join(HERE, name)
    if not os.path.isfile(p):
        return None
    return np.asarray(Image.open(p).convert("RGB"))


def iron_col(p, tex=None):
    x, y, z = p
    u = math.atan2(x, -z) / (2 * math.pi) + 0.5
    v = np.clip((y + 1.2) / 2.5, 0, 1)
    # highlight along keel (center front)
    keel = math.exp(-((x / 0.18) ** 2)) * max(0.0, -z)
    base = lerp(IRON_D, IRON_H, 0.35 + 0.45 * min(keel, 1.0))
    # slight vertical banding
    base = lerp(base, IRON, 0.25 + 0.15 * math.sin(y * 6.0))
    if tex is not None:
        h, w = tex.shape[:2]
        tx = int(u * (w - 1)) % w
        ty = int((1 - v) * (h - 1)) % h
        tcol = tex[ty, tx] / 255.0
        base = 0.55 * base + 0.45 * tcol * np.array([0.85, 0.87, 0.9])
    return np.clip(base, 0, 1)


def halfwidth(u):
    """u=0 neck, 1 bottom. Shoulders wide, waist cinched, slight flare."""
    if u < 0.18:
        return lerp(0.95, 1.18, u / 0.18)
    if u < 0.42:
        return lerp(1.18, 1.22, (u - 0.18) / 0.24)
    if u < 0.78:
        return lerp(1.22, 0.86, (u - 0.42) / 0.36)
    return lerp(0.86, 0.98, (u - 0.78) / 0.22)


def chest_depth(u):
    """Front prominence."""
    return 0.52 + 0.16 * math.sin(math.pi * np.clip(u, 0, 1))


def keel_amt(v, u):
    """Central ridge, strongest on chest."""
    return 0.14 * math.exp(-((v) ** 2) / 0.12) * (0.55 + 0.45 * math.sin(math.pi * u))


def in_neck(u, v, hw):
    x = abs(v) * hw
    return u < 0.13 and x < 0.38 + (0.13 - u) * 1.6


def in_armhole(u, v, hw):
    return False


def build_plate(mesh, sign_z, tex, nu=22, nv=24, front=True):
    """sign_z = -1 front, +1 back."""
    pts = np.zeros((nu, nv, 3))
    uvs = np.zeros((nu, nv, 2))
    cols = np.zeros((nu, nv, 3))
    keep = np.ones((nu, nv), dtype=bool)
    for i in range(nu):
        u = i / (nu - 1)
        y = lerp(1.02, -1.08, u)
        hw = halfwidth(u)
        depth = chest_depth(u)
        for j in range(nv):
            v = lerp(-1.0, 1.0, j / (nv - 1))
            x = v * hw
            k = keel_amt(v, u) if front else keel_amt(v, u) * 0.25
            z = sign_z * (depth + k)
            # wrap sides slightly toward ±Z=0
            side = abs(v)
            if side > 0.72:
                z *= lerp(1.0, 0.55, (side - 0.72) / 0.28)
            p = np.array([x, y, z])
            pts[i, j] = p
            uvs[i, j] = (j / (nv - 1), u)
            cols[i, j] = iron_col(p, tex)
            keep[i, j] = not (in_neck(u, v, hw) or in_armhole(u, v, hw))

    idx = np.full((nu, nv), -1, dtype=np.int32)
    for i in range(nu):
        for j in range(nv):
            if keep[i, j]:
                idx[i, j] = mesh.add_v(pts[i, j], uvs[i, j], cols[i, j])
    for i in range(nu - 1):
        for j in range(nv - 1):
            a, b = idx[i, j], idx[i + 1, j]
            c, d = idx[i + 1, j + 1], idx[i, j + 1]
            if min(int(a), int(b), int(c), int(d)) < 0:
                continue
            if front:
                mesh.add_q(a, b, c, d)
            else:
                mesh.add_q(a, d, c, b)


def add_rim(mesh, path, radius, col):
    tube(mesh, path, [radius] * len(path), 8, lambda t, j: col)


def pauldron(steel, side, tex):
    """Spherical overlapping spaulder lames wrapping the shoulder."""
    n_lames = 5
    origin = np.array([side * 0.82, 0.78, 0.02])
    for k in range(n_lames):
        t = k / (n_lames - 1)
        # each lame is a band of a sphere, sliding down the arm
        rad = lerp(0.42, 0.50, t)
        origin_k = origin + np.array([side * 0.16 * t, -0.42 * t, 0.02 * t])
        th0 = lerp(math.radians(25), math.radians(55), t)
        th1 = lerp(math.radians(95), math.radians(125), t)
        ph0, ph1 = math.radians(-95), math.radians(95)
        nu, nv = 9, 16
        pts = np.zeros((nu, nv, 3))
        uvs = np.zeros((nu, nv, 2))
        cols = np.zeros((nu, nv, 3))
        for i in range(nu):
            th = lerp(th0, th1, i / (nu - 1))
            for j in range(nv):
                ph = lerp(ph0, ph1, j / (nv - 1))
                # local sphere: X = out, Y = up, Z = front/back
                lx = side * rad * math.sin(th) * math.cos(ph * 0.15)
                # wrap around Z (front-back) and down
                x = origin_k[0] + side * rad * math.sin(th)
                y = origin_k[1] + rad * math.cos(th)
                z = origin_k[2] + rad * math.sin(th) * math.sin(ph) * 0.85
                # extra wrap so it cups the shoulder
                x = origin_k[0] + side * (rad * math.sin(th) * math.cos(ph * 0.35))
                p = np.array([x, y, z])
                pts[i, j] = p
                uvs[i, j] = (j / (nv - 1), i / (nu - 1))
                cols[i, j] = iron_col(p, tex)
        add_shell_indexed(steel, pts, uvs, cols, thick=0.03, center=origin_k)
        uv_sphere(
            steel,
            origin_k + np.array([side * rad * 0.35, rad * 0.15, 0.12]),
            0.035,
            0.035,
            0.035,
            5,
            8,
            IRON_H,
        )


def build_armor(tex):
    steel = Mesh(mat="steel")
    leather = Mesh(mat="leather")
    gold = Mesh(mat="gold")

    build_plate(steel, -1.0, tex, front=True)
    build_plate(steel, 1.0, tex, front=False)

    # neck gorget ring
    n = 28
    path = []
    for i in range(n):
        a = i / (n - 1) * math.pi * 2
        path.append(np.array([0.42 * math.sin(a), 0.98, -0.08 * math.cos(a)]))
    add_rim(steel, path, 0.045, IRON_H)

    # waist flare rim (front)
    path = []
    for i in range(16):
        v = lerp(-0.9, 0.9, i / 15)
        hw = halfwidth(1.0)
        x = v * hw
        y = -1.08
        z = -chest_depth(1.0) - keel_amt(v, 1.0) * 0.4
        path.append(np.array([x, y, z]))
    add_rim(steel, path, 0.03, IRON)

    pauldron(steel, -1, tex)
    pauldron(steel, 1, tex)

    # side leather straps
    for side in (-1.0, 1.0):
        o = np.array([side * 0.92, 0.15, -0.15])
        d = np.array([side * 0.92, 0.15, 0.35])
        segs = [lerp(o, d, t / 5) for t in range(6)]
        tube(leather, segs, [0.04] * 6, 6, lambda t, j: STRAP)
        # buckle
        uv_sphere(gold, lerp(o, d, 0.5) + np.array([side * 0.02, 0, 0]), 0.05, 0.035, 0.04, 5, 8, GOLD)

    # chest rivets along keel sides
    for y in np.linspace(0.55, -0.7, 7):
        for s in (-1, 1):
            u = (0.95 - y) / 2.0
            p = np.array([s * 0.16, y, -chest_depth(u) - 0.12])
            uv_sphere(steel, p, 0.035, 0.035, 0.035, 5, 8, IRON_H)

    return {"steel": steel, "gold": gold, "leather": leather}


def main():
    tex = load_tex("tex_iron.jpg")
    print("building armor...")
    parts = build_armor(tex)
    for k, m in parts.items():
        print(k, "verts", len(m.verts), "faces", len(m.faces))
    export_obj(parts, os.path.join(HERE, "ArmaduraFerro.obj"))
    render(
        parts,
        os.path.join(HERE, "preview_produto.jpg"),
        w=1000,
        h=900,
        cam=[0.15, 0.55, -5.2],
        target=[0.0, 0.15, 0.0],
        bg=(1.0, 1.0, 1.0),
    )
    render(
        parts,
        os.path.join(HERE, "preview_estudio.jpg"),
        w=1000,
        h=900,
        cam=[-3.8, 1.6, -4.0],
        target=[0.0, 0.15, 0.0],
        bg=(0.08, 0.08, 0.09),
    )
    lua_path = os.path.join(HERE, "ArmaduraFerro_R6_CommandBar.lua")
    write_lua_quantized(parts, lua_path)
    # patch accessory to weld to Torso instead of Head
    with open(lua_path, encoding="utf-8") as f:
        lua = f.read()
    lua = lua.replace('acc.Name = "CapaceteRomanoCenturiao"', 'acc.Name = "ArmaduraFerroPeitoral"')
    lua = lua.replace('hatAtt.Name = "HatAttachment"', 'hatAtt.Name = "BodyFrontAttachment"')
    lua = lua.replace("hatAtt.Position = Vector3.new(0, 0.6, 0)", "hatAtt.Position = Vector3.new(0, 0, 0)")
    lua = lua.replace("Head", "Torso")
    lua = lua.replace("Capacete Romano", "Armadura de Ferro")
    lua = lua.replace("Capacete", "Armadura")
    with open(lua_path, "w", encoding="utf-8") as f:
        f.write(lua)
    root = os.path.join(os.path.dirname(HERE), "ArmaduraFerro_R6_CommandBar.lua")
    with open(root, "w", encoding="utf-8") as f:
        f.write(lua)
    print("done")


if __name__ == "__main__":
    main()
