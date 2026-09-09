#!/usr/bin/env python3
"""Professional Roman centurion galea — mesh, preview, OBJ, Roblox Lua."""

from __future__ import annotations

import math
import os
import struct
import zlib
from dataclasses import dataclass, field

import numpy as np
from numba import njit
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = ROOT

# ---------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------


@dataclass
class Mesh:
    verts: list = field(default_factory=list)
    faces: list = field(default_factory=list)
    uvs: list = field(default_factory=list)
    colors: list = field(default_factory=list)
    mat: str = "steel"

    def add_v(self, p, uv=(0.0, 0.0), col=(0.78, 0.79, 0.82)):
        self.verts.append(np.asarray(p, dtype=np.float64))
        self.uvs.append((float(uv[0]), float(uv[1])))
        self.colors.append(np.asarray(col, dtype=np.float64))
        return len(self.verts) - 1

    def add_f(self, a, b, c, flip=False):
        self.faces.append((a, c, b) if flip else (a, b, c))

    def add_q(self, a, b, c, d, flip=False):
        self.add_f(a, b, c, flip)
        self.add_f(a, c, d, flip)

    def np_verts(self):
        if not self.verts:
            return np.zeros((0, 3))
        return np.stack(self.verts, 0)

    def np_faces(self):
        if not self.faces:
            return np.zeros((0, 3), dtype=np.int32)
        return np.asarray(self.faces, dtype=np.int32)

    def np_cols(self):
        if not self.colors:
            return np.zeros((0, 3))
        return np.stack(self.colors, 0)

    def np_uvs(self):
        if not self.uvs:
            return np.zeros((0, 2))
        return np.asarray(self.uvs, dtype=np.float64)

    def append(self, other: "Mesh"):
        o = len(self.verts)
        self.verts.extend(other.verts)
        self.uvs.extend(other.uvs)
        self.colors.extend(other.colors)
        for a, b, c in other.faces:
            self.faces.append((a + o, b + o, c + o))

    def transform(self, fn):
        self.verts = [fn(v) for v in self.verts]


def vnorm(v):
    n = np.linalg.norm(v)
    return v if n < 1e-12 else v / n


def lerp(a, b, t):
    return a + (b - a) * t


def bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3


def look_y(dir_):
    d = vnorm(dir_)
    helper = np.array([0.0, 0.0, 1.0]) if abs(d[1]) > 0.97 else np.array([0.0, 1.0, 0.0])
    r = np.cross(d, helper)
    if np.linalg.norm(r) < 1e-9:
        r = np.cross(d, np.array([1.0, 0.0, 0.0]))
    r = vnorm(r)
    z = vnorm(np.cross(r, d))
    return r, d, z


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

STEEL = np.array([0.77, 0.785, 0.82])
STEEL_D = np.array([0.48, 0.50, 0.53])
GOLD = np.array([0.83, 0.66, 0.23])
GOLD_D = np.array([0.55, 0.40, 0.12])
RED = np.array([0.82, 0.08, 0.10])
RED_D = np.array([0.55, 0.05, 0.07])
RED_H = np.array([0.92, 0.18, 0.16])
LEATHER_C = np.array([0.07, 0.06, 0.06])
LINER = np.array([0.04, 0.035, 0.035])


def grid_surface(mesh: Mesh, pts, uvs, cols, closed_u=False, closed_v=False, flip=False):
    """pts: (nu, nv, 3)"""
    nu, nv = pts.shape[:2]
    idx = np.zeros((nu, nv), dtype=np.int32)
    for i in range(nu):
        for j in range(nv):
            idx[i, j] = mesh.add_v(pts[i, j], uvs[i, j], cols[i, j])
    nu_e = nu if closed_u else nu - 1
    nv_e = nv if closed_v else nv - 1
    for i in range(nu_e):
        i1 = (i + 1) % nu if closed_u else i + 1
        for j in range(nv_e):
            j1 = (j + 1) % nv if closed_v else j + 1
            mesh.add_q(idx[i, j], idx[i1, j], idx[i1, j1], idx[i, j1], flip=flip)


def thicken_offset(pts, amount, center=None):
    """pts (nu,nv,3) -> inward offset along outward normal."""
    nu, nv = pts.shape[:2]
    out = np.zeros_like(pts)
    c = np.asarray(center if center is not None else (0.0, 0.45, 0.0), dtype=np.float64)
    for i in range(nu):
        for j in range(nv):
            i0, i1 = max(0, i - 1), min(nu - 1, i + 1)
            j0, j1 = max(0, j - 1), min(nv - 1, j + 1)
            du = pts[i1, j] - pts[i0, j]
            dv = pts[i, j1] - pts[i, j0]
            n = np.cross(du, dv)
            if np.linalg.norm(n) < 1e-10:
                n = pts[i, j] - c
            n = vnorm(n)
            if np.dot(n, pts[i, j] - c) < 0:
                n = -n
            out[i, j] = pts[i, j] - n * amount
    return out


def add_shell(mesh, pts, uvs, cols, thick=0.045, closed_u=False, closed_v=False):
    inner = thicken_offset(pts, thick)
    grid_surface(mesh, pts, uvs, cols, closed_u, closed_v, flip=False)
    grid_surface(mesh, inner, uvs, np.clip(cols * 0.25, 0, 1), closed_u, closed_v, flip=True)
    nu, nv = pts.shape[:2]
    # stitch open edges
    def stitch_row(i_outer, i_inner_pts, j_range, reverse=False):
        pass

    # v=0 edge
    if not closed_v:
        for i in range(nu - 1):
            a = len(mesh.verts)  # too late, need indices
        # handled below with stored indices — redo via extra pass using last verts
    # Simpler: stitch using a second index build
    return inner


def add_shell_indexed(mesh: Mesh, pts, uvs, cols, thick=0.045, closed_u=False, center=None):
    nu, nv = pts.shape[:2]
    inner = thicken_offset(pts, thick, center=center)
    outer_i = np.zeros((nu, nv), dtype=np.int32)
    inner_i = np.zeros((nu, nv), dtype=np.int32)
    for i in range(nu):
        for j in range(nv):
            outer_i[i, j] = mesh.add_v(pts[i, j], uvs[i, j], cols[i, j])
            inner_i[i, j] = mesh.add_v(inner[i, j], uvs[i, j], cols[i, j] * 0.22)
    nu_e = nu if closed_u else nu - 1
    for i in range(nu_e):
        i1 = (i + 1) % nu if closed_u else i + 1
        for j in range(nv - 1):
            mesh.add_q(outer_i[i, j], outer_i[i1, j], outer_i[i1, j + 1], outer_i[i, j + 1])
            mesh.add_q(inner_i[i, j], inner_i[i, j + 1], inner_i[i1, j + 1], inner_i[i1, j])
    # rim at v=0 and v=nv-1
    for i in range(nu_e):
        i1 = (i + 1) % nu if closed_u else i + 1
        mesh.add_q(outer_i[i, 0], inner_i[i, 0], inner_i[i1, 0], outer_i[i1, 0])
        mesh.add_q(
            outer_i[i, nv - 1],
            outer_i[i1, nv - 1],
            inner_i[i1, nv - 1],
            inner_i[i, nv - 1],
        )
    if not closed_u:
        for j in range(nv - 1):
            mesh.add_q(outer_i[0, j], outer_i[0, j + 1], inner_i[0, j + 1], inner_i[0, j])
            mesh.add_q(
                outer_i[nu - 1, j],
                inner_i[nu - 1, j],
                inner_i[nu - 1, j + 1],
                outer_i[nu - 1, j + 1],
            )


def uv_sphere(mesh: Mesh, c, rx, ry, rz, nu, nv, col, u0=0, u1=1, v0=0, v1=1, hemisphere=False):
    pts = np.zeros((nu, nv, 3))
    uvs = np.zeros((nu, nv, 2))
    cols = np.zeros((nu, nv, 3))
    for i in range(nu):
        uu = lerp(u0, u1, i / (nu - 1))
        theta = uu * math.pi * (0.5 if hemisphere else 1.0)  # 0 top
        for j in range(nv):
            vv = lerp(v0, v1, j / (nv - 1))
            phi = vv * math.pi * 2
            x = rx * math.sin(theta) * math.sin(phi)
            y = ry * math.cos(theta)
            z = rz * math.sin(theta) * math.cos(phi)
            pts[i, j] = c + np.array([x, y, z])
            uvs[i, j] = (vv, uu)
            cols[i, j] = col
    grid_surface(mesh, pts, uvs, cols, closed_u=False, closed_v=True)


def icosphere_like(mesh: Mesh, c, r, col, nlat=8, nlon=12):
    uv_sphere(mesh, c, r, r, r, nlat, nlon, col)


def tube(mesh: Mesh, path, radii, ncirc, col_fn, closed=False):
    n = len(path)
    pts = np.zeros((n, ncirc, 3))
    uvs = np.zeros((n, ncirc, 2))
    cols = np.zeros((n, ncirc, 3))
    for i, p in enumerate(path):
        d = path[min(n - 1, i + 1)] - path[max(0, i - 1)]
        right, _, fwd_z = look_y(d)
        # look_y returns right, dir, z with Y=dir. Circle in right/z plane
        for j in range(ncirc):
            a = j / ncirc * math.pi * 2
            off = (right * math.cos(a) + fwd_z * math.sin(a)) * radii[i]
            pts[i, j] = p + off
            uvs[i, j] = (j / ncirc, i / max(1, n - 1))
            cols[i, j] = col_fn(i / max(1, n - 1), j / ncirc)
    grid_surface(mesh, pts, uvs, cols, closed_u=False, closed_v=True)


# ---------------------------------------------------------------------------
# Helmet construction
# ---------------------------------------------------------------------------


def swirl(x, y, z, k=3.2):
    a = math.atan2(x, -z)
    r = math.hypot(x, z)
    return math.sin(k * a + 4 * r) * math.cos(5 * y + 2 * a)


def steel_col(p, tex=None, size=None):
    x, y, z = p
    u = math.atan2(x, -z) / (2 * math.pi) + 0.5
    v = np.clip((y + 0.6) / 2.4, 0, 1)
    base = STEEL.copy()
    s = swirl(x, y, z)
    base = lerp(base, STEEL_D, 0.22 * (0.5 + 0.5 * s))
    if tex is not None:
        h, w = tex.shape[:2]
        tx = int(u * (w - 1)) % w
        ty = int((1 - v) * (h - 1)) % h
        tcol = tex[ty, tx] / 255.0
        base = 0.82 * base + 0.18 * tcol
    return np.clip(base, 0, 1)


def build_helmet(steel_tex=None, hair_tex=None, gold_tex=None):
    steel = Mesh(mat="steel")
    gold = Mesh(mat="gold")
    hair = Mesh(mat="hair")
    leather = Mesh(mat="leather")

    # ---- 1. Skull lathe (open face) ----
    n_th, n_pr = 72, 22
    # profile: theta from top (0) to just under brow (~100 deg)
    thetas = np.linspace(0.0, math.radians(108), n_pr)
    # azimuth 0 = front (-Z)
    azims = np.linspace(0.0, math.pi * 2, n_th, endpoint=False)

    def skull_point(theta, az):
        rx, ry, rz = 1.18, 1.10, 1.02
        # slight front visor jut
        jut = 0.06 * math.sin(theta) ** 2 * math.cos(az) ** 2 * (1 if math.cos(az) > 0 else 0)
        # az 0 is front, cos(az)>0 is front
        x = (rx + jut * 0.3) * math.sin(theta) * math.sin(az)
        y = 0.52 + ry * math.cos(theta)
        z = -(rz + jut) * math.sin(theta) * math.cos(az)
        # flatten a ridge on top for crest
        if theta < math.radians(18):
            x *= 0.92
        return np.array([x, y, z])

    def face_open(theta, az):
        aa = az if az <= math.pi else az - 2 * math.pi
        return abs(aa) < math.radians(50) and theta > math.radians(66)

    # Build only kept quads as a mask grid — use NaN for holes then skip
    pts = np.zeros((n_pr, n_th, 3))
    keep = np.ones((n_pr, n_th), dtype=bool)
    uvs = np.zeros((n_pr, n_th, 2))
    cols = np.zeros((n_pr, n_th, 3))
    for i, th in enumerate(thetas):
        for j, az in enumerate(azims):
            p = skull_point(th, az)
            # engraving micro-displace
            nrm_approx = vnorm(p - np.array([0.0, 0.52, 0.0]))
            p = p + nrm_approx * (0.003 * swirl(p[0], p[1], p[2], 4.0))
            pts[i, j] = p
            keep[i, j] = not face_open(th, az)
            uvs[i, j] = (j / n_th, i / (n_pr - 1))
            cols[i, j] = steel_col(p, steel_tex)

    # add outer+inner verts only for kept, skip quads with any hole
    oi = np.full((n_pr, n_th), -1, dtype=np.int32)
    for i in range(n_pr):
        for j in range(n_th):
            if not keep[i, j]:
                continue
            oi[i, j] = steel.add_v(pts[i, j], uvs[i, j], cols[i, j])

    def qsafe(idx, i, j, i1, j1, flip=False):
        a, b, c, d = idx[i, j], idx[i1, j], idx[i1, j1], idx[i, j1]
        if min(a, b, c, d) < 0:
            return
        steel.add_q(a, b, c, d, flip=flip)

    for i in range(n_pr - 1):
        for j in range(n_th):
            j1 = (j + 1) % n_th
            qsafe(oi, i, j, i + 1, j1, False)

    # ---- 2. Brow band ----
    nb, nbb = 28, 5
    brow = np.zeros((nbb, nb, 3))
    buv = np.zeros((nbb, nb, 2))
    bcol = np.zeros((nbb, nb, 3))
    for i in range(nbb):
        t = i / (nbb - 1)
        y = lerp(0.36, 0.58, t)
        wth = lerp(0.10, 0.055, t)
        for j in range(nb):
            a = lerp(-math.radians(82), math.radians(82), j / (nb - 1))
            r = 1.20 + 0.02 * math.sin(t * math.pi)
            x = r * math.sin(a)
            z = -r * math.cos(a) * 0.92
            p = np.array([x, y, z])
            brow[i, j] = p
            buv[i, j] = (j / (nb - 1), t)
            bcol[i, j] = steel_col(p, steel_tex)
    add_shell_indexed(steel, brow, buv, bcol, thick=0.05, closed_u=False)

    # visor lip
    lip = np.zeros((3, 11, 3))
    luv = np.zeros((3, 11, 2))
    lcol = np.zeros((3, 11, 3))
    for i in range(3):
        for j in range(11):
            t = j / 10
            a = lerp(-0.55, 0.55, t)
            y = 0.38 - i * 0.04
            z = -1.05 - i * 0.04
            p = np.array([a * 1.05, y, z])
            lip[i, j] = p
            luv[i, j] = (t, i / 2)
            lcol[i, j] = STEEL
    add_shell_indexed(steel, lip, luv, lcol, 0.035)

    # ---- 3. Cheek guards ----
    def make_cheek(side):
        nu, nv = 14, 12
        pts = np.zeros((nu, nv, 3))
        uvs = np.zeros((nu, nv, 2))
        cols = np.zeros((nu, nv, 3))
        for i in range(nu):
            u = i / (nu - 1)  # 0 top .. 1 bottom
            for j in range(nv):
                v = j / (nv - 1)  # 0 front .. 1 back
                # round the bottom
                vspan = 1.0 - 0.45 * max(0, u - 0.62) / 0.38
                v2 = 0.5 + (v - 0.5) * vspan
                y = lerp(0.46, -0.58, u) + 0.04 * math.sin(u * math.pi)
                z = lerp(-0.42, 0.50, v2)
                flare = 0.04 * u * u
                x = side * (1.14 + flare + 0.03 * math.sin(v * math.pi))
                # pull bottom slightly in
                if u > 0.8:
                    x = side * (abs(x) - 0.04 * (u - 0.8) / 0.2)
                p = np.array([x, y, z])
                # swirl engraving displace
                p[0] += side * 0.01 * swirl(p[0], p[1], p[2], 5.0)
                pts[i, j] = p
                uvs[i, j] = (v, u)
                cols[i, j] = steel_col(p, steel_tex)
        add_shell_indexed(steel, pts, uvs, cols, 0.042)

    make_cheek(-1)
    make_cheek(1)

    # ---- 4. Neck guard ----
    nn, nm = 10, 20
    neck = np.zeros((nn, nm, 3))
    nuv = np.zeros((nn, nm, 2))
    ncol = np.zeros((nn, nm, 3))
    for i in range(nn):
        u = i / (nn - 1)
        for j in range(nm):
            v = j / (nm - 1)
            a = lerp(math.radians(108), math.radians(252), v)
            y = lerp(0.28, -0.18, u) - 0.06 * u
            r = 1.08 + 0.28 * u
            x = r * math.sin(a)
            z = -r * math.cos(a) * 0.9 + 0.12 * u
            p = np.array([x, y, z])
            neck[i, j] = p
            nuv[i, j] = (v, u)
            ncol[i, j] = steel_col(p, steel_tex)
    add_shell_indexed(steel, neck, nuv, ncol, 0.04)

    # ---- 5. Crest box ----
    crn, crm = 3, 12
    box = np.zeros((crn, crm, 3))
    cuv = np.zeros((crn, crm, 2))
    ccol = np.zeros((crn, crm, 3))
    for i in range(crn):
        x = lerp(-0.08, 0.08, i / (crn - 1))
        for j in range(crm):
            t = j / (crm - 1)
            z = lerp(-0.58, 0.80, t)
            y = 1.50 + 0.10 * math.sin(t * math.pi) + (0.02 if i == 1 else 0)
            p = np.array([x, y, z])
            box[i, j] = p
            cuv[i, j] = (t, i / 2)
            ccol[i, j] = STEEL_D
    add_shell_indexed(steel, box, cuv, ccol, 0.03)

    # ---- 6. Rivets ----
    def rivet(p, n, r=0.055, mat="steel"):
        m = steel if mat == "steel" else gold
        col = STEEL * 1.05 if mat == "steel" else GOLD
        # hemisphere along n
        n = vnorm(n)
        # build small hemisphere
        nlat, nlon = 5, 8
        # orthonormal
        helper = np.array([0.0, 1.0, 0.0]) if abs(n[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        tvec = vnorm(np.cross(helper, n))
        bvec = vnorm(np.cross(n, tvec))
        pts = np.zeros((nlat, nlon, 3))
        uvs = np.zeros((nlat, nlon, 2))
        cols = np.zeros((nlat, nlon, 3))
        for i in range(nlat):
            th = (i / (nlat - 1)) * math.pi * 0.5
            for j in range(nlon):
                ph = j / nlon * math.pi * 2
                local = tvec * math.sin(th) * math.cos(ph) + bvec * math.sin(th) * math.sin(ph) + n * math.cos(th)
                pts[i, j] = p + local * r
                uvs[i, j] = (j / nlon, i / (nlat - 1))
                cols[i, j] = col
        grid_surface(m, pts, uvs, cols, closed_v=True)

    # brow rivets
    for k in range(9):
        a = lerp(-math.radians(70), math.radians(70), k / 8)
        r = 1.22
        p = np.array([r * math.sin(a), 0.56, -r * math.cos(a) * 0.92])
        rivet(p, vnorm(p - np.array([0, 0.3, 0])), 0.058)
    # cheek rivets
    for side in (-1, 1):
        spots = [
            (0.40, -0.32),
            (0.12, -0.34),
            (-0.18, -0.28),
            (-0.40, -0.06),
            (-0.38, 0.20),
            (-0.12, 0.34),
            (0.18, 0.32),
            (0.40, 0.16),
        ]
        for y, z in spots:
            p = np.array([side * 1.20, y, z])
            rivet(p, np.array([side, 0.0, 0.0]), 0.05)
    # neck rivets
    for k in range(7):
        a = lerp(math.radians(125), math.radians(235), k / 6)
        p = np.array([1.22 * math.sin(a), -0.02, -1.05 * math.cos(a) + 0.15])
        rivet(p, vnorm(np.array([math.sin(a), -0.4, -math.cos(a)])), 0.05)

    # ---- 7. Hinges (gold) ----
    for side in (-1, 1):
        c = np.array([side * 1.16, 0.40, -0.22])
        path = [c + np.array([0, 0, -0.10]), c, c + np.array([0, 0, 0.10])]
        tube(gold, path, [0.055, 0.06, 0.055], 8, lambda t, j: GOLD_D)

    # ---- 8. Lion bosses ----
    def lion(side):
        origin = np.array([side * 1.22, 0.26, -0.30])
        out = np.array([side, 0.05, -0.15])
        out = vnorm(out)
        helper = np.array([0.0, 1.0, 0.0])
        tvec = vnorm(np.cross(helper, out))
        bvec = vnorm(np.cross(out, tvec))

        def L(lx, ly, lz):
            return origin + tvec * lx + bvec * ly + out * lz

        uv_sphere(gold, L(0, 0, 0.02), 0.20, 0.20, 0.16, 8, 12, GOLD_D)
        uv_sphere(gold, L(0, -0.02, 0.12), 0.13, 0.12, 0.12, 7, 10, GOLD)
        uv_sphere(gold, L(0, -0.05, 0.22), 0.07, 0.055, 0.08, 6, 8, GOLD * 1.1)
        uv_sphere(gold, L(0, -0.03, 0.29), 0.03, 0.025, 0.03, 4, 6, GOLD_D)
        uv_sphere(gold, L(-0.055, 0.04, 0.20), 0.02, 0.02, 0.02, 4, 6, LINER)
        uv_sphere(gold, L(0.055, 0.04, 0.20), 0.02, 0.02, 0.02, 4, 6, LINER)
        for k in range(10):
            a = k / 10 * math.pi * 2
            q = L(math.cos(a) * 0.18, math.sin(a) * 0.18, -0.02)
            uv_sphere(gold, q, 0.07, 0.07, 0.06, 5, 8, GOLD if k % 2 == 0 else GOLD_D)
        # ears
        uv_sphere(gold, L(-0.09, 0.14, 0.08), 0.035, 0.05, 0.03, 5, 6, GOLD)
        uv_sphere(gold, L(0.09, 0.14, 0.08), 0.035, 0.05, 0.03, 5, 6, GOLD)

    lion(-1)
    lion(1)

    # ---- 9. Horsehair crest (width locked to +X) ----
    c0 = np.array([0.0, 1.56, -0.52])
    c1 = np.array([0.0, 1.58, 0.05])
    c2 = np.array([0.0, 1.54, 0.85])
    c3 = np.array([0.0, 0.85, 1.85])
    npath = 48
    path = [bezier(c0, c1, c2, c3, i / (npath - 1)) for i in range(npath)]

    def hair_col(t, j):
        base = lerp(RED_H, RED, min(1.0, t * 0.7))
        if t > 0.55:
            base = lerp(RED, RED_D, (t - 0.55) / 0.45)
        if hair_tex is not None:
            hh, ww = hair_tex.shape[:2]
            tx = int(j * (ww - 1)) % ww
            ty = int((1 - t) * (hh - 1)) % hh
            tc = hair_tex[ty, tx] / 255.0
            base = 0.62 * base + 0.38 * tc
        return np.clip(base, 0, 1)

    def crest_rx(t):
        if t < 0.10:
            return lerp(0.07, 0.15, t / 0.10)
        if t < 0.45:
            return 0.15
        return lerp(0.15, 0.022, (t - 0.45) / 0.55)

    def crest_ry(t):
        if t < 0.10:
            return lerp(0.11, 0.26, t / 0.10)
        if t < 0.42:
            return 0.26
        return lerp(0.26, 0.028, (t - 0.42) / 0.58)

    ncirc = 16
    n = len(path)
    hp = np.zeros((n, ncirc, 3))
    hu = np.zeros((n, ncirc, 2))
    hc = np.zeros((n, ncirc, 3))
    right = np.array([1.0, 0.0, 0.0])
    prev_bn = np.array([0.0, 1.0, 0.0])
    for i, pnt in enumerate(path):
        d = path[min(n - 1, i + 1)] - path[max(0, i - 1)]
        T = vnorm(d)
        bn = np.cross(T, right)
        if np.linalg.norm(bn) < 1e-6:
            bn = prev_bn
        bn = vnorm(bn)
        if np.dot(bn, prev_bn) < 0:
            bn = -bn
        prev_bn = bn
        tt = i / (n - 1)
        rx, ry = crest_rx(tt), crest_ry(tt)
        for j in range(ncirc):
            a = j / ncirc * math.pi * 2
            off = right * math.cos(a) * rx + bn * (math.sin(a) * ry + ry)
            hp[i, j] = pnt + off
            hu[i, j] = (j / ncirc, tt)
            hc[i, j] = hair_col(tt, j / ncirc)
    grid_surface(hair, hp, hu, hc, closed_v=True)
    uv_sphere(hair, path[0], crest_rx(0) * 1.05, crest_ry(0), crest_rx(0) * 1.05, 6, 10, RED_H)
    rng = np.random.default_rng(7)
    for k in range(22):
        t0 = 0.62 + 0.36 * rng.random()
        pnt = bezier(c0, c1, c2, c3, t0)
        dirw = vnorm(np.array([rng.normal(0, 0.12), -0.62 + rng.normal(0, 0.08), 0.78]))
        leng = 0.4 + 0.55 * (1 - t0)
        nseg = 7
        wpath = [pnt + dirw * (leng * s / (nseg - 1)) for s in range(nseg)]
        wr = [0.016 * (1 - 0.75 * s / (nseg - 1)) for s in range(nseg)]
        tube(hair, wpath, wr, 5, lambda ttt, j: RED_D)

    # ---- 10. Leather straps ----
    def strap(side, origin, dest, segs=6):
        path = []
        for k in range(segs):
            t = k / (segs - 1)
            mid = lerp(origin, dest, t)
            mid = mid + np.array([side * 0.04, 0.07, 0.0]) * math.sin(t * math.pi)
            path.append(mid)
        tube(leather, path, [0.035] * segs, 6, lambda t, j: LEATHER_C)

    for side in (-1, 1):
        o1 = np.array([side * 1.14, -0.50, -0.12])
        strap(side, o1, o1 + np.array([side * 0.06, -0.85, 0.08]))
        o2 = np.array([side * 1.14, -0.48, 0.18])
        strap(side, o2, o2 + np.array([side * 0.08, -0.62, 0.30]))

    return {"steel": steel, "gold": gold, "hair": hair, "leather": leather}


# ---------------------------------------------------------------------------
# Normals + lighting rasterizer
# ---------------------------------------------------------------------------


def vertex_normals(v, f):
    n = np.zeros_like(v)
    if len(f) == 0:
        return n
    v0, v1, v2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    for i in range(3):
        np.add.at(n, f[:, i], fn)
    lens = np.linalg.norm(n, axis=1, keepdims=True)
    lens = np.maximum(lens, 1e-9)
    return n / lens


def shade_vertices(v, n, albedo, metallic, cam, lights):
    view = cam[None, :] - v
    view /= np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-9)
    ndv = np.clip((n * view).sum(1, keepdims=True), 0, 1)
    fres = 0.04 + 0.96 * (1.0 - ndv) ** 5
    col = albedo * 0.22
    for lp, lc, intens in lights:
        ldir = lp[None, :] - v
        ldir /= np.maximum(np.linalg.norm(ldir, axis=1, keepdims=True), 1e-9)
        ndl = np.clip((n * ldir).sum(1, keepdims=True), 0, 1)
        h = vnorm_rows(ldir + view)
        ndh = np.clip((n * h).sum(1, keepdims=True), 0, 1)
        spec = ndh ** (80 if metallic > 0.5 else 20)
        diff = albedo * ndl * (1.0 - metallic * 0.65)
        sp = spec * fres * metallic * 1.4 + spec * (1 - metallic) * 0.15
        col = col + intens * (diff + sp) * lc[None, :]
    # fake env from reflection
    r = vnorm_rows(2 * ndv * n - view)
    env = 0.18 + 0.22 * np.clip(r[:, 1:2] * 0.5 + 0.5, 0, 1)
    col = col + env * fres * (0.25 + 0.5 * metallic)
    return np.clip(col, 0, 1)


def vnorm_rows(x):
    return x / np.maximum(np.linalg.norm(x, axis=1, keepdims=True), 1e-9)


@njit
def raster_gouraud(sx, sy, sz, cr, cg, cb, zbuf, out, w, h):
    ntri = sx.shape[0]
    for t in range(ntri):
        x0, y0, z0 = sx[t, 0], sy[t, 0], sz[t, 0]
        x1, y1, z1 = sx[t, 1], sy[t, 1], sz[t, 1]
        x2, y2, z2 = sx[t, 2], sy[t, 2], sz[t, 2]
        if z0 <= 0.05 or z1 <= 0.05 or z2 <= 0.05:
            continue
        minx = int(max(0, math.floor(min(x0, x1, x2))))
        maxx = int(min(w - 1, math.ceil(max(x0, x1, x2))))
        miny = int(max(0, math.floor(min(y0, y1, y2))))
        maxy = int(min(h - 1, math.ceil(max(y0, y1, y2))))
        if minx > maxx or miny > maxy:
            continue
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if area <= 1e-6:
            continue  # backface (y-down screen, CCW)
        inv_a = 1.0 / area
        r0, g0, b0 = cr[t, 0], cg[t, 0], cb[t, 0]
        r1, g1, b1 = cr[t, 1], cg[t, 1], cb[t, 1]
        r2, g2, b2 = cr[t, 2], cg[t, 2], cb[t, 2]
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) * inv_a
                w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) * inv_a
                w2 = ((x0 - px) * (y1 - py) - (x1 - px) * (y0 - py)) * inv_a
                if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
                    continue
                z = w0 * z0 + w1 * z1 + w2 * z2
                if z < zbuf[y, x]:
                    zbuf[y, x] = z
                    out[y, x, 0] = w0 * r0 + w1 * r1 + w2 * r2
                    out[y, x, 1] = w0 * g0 + w1 * g1 + w2 * g2
                    out[y, x, 2] = w0 * b0 + w1 * b1 + w2 * b2


def project(v, cam, target, up, fov, w, h):
    f = vnorm(target - cam)
    r = vnorm(np.cross(f, up))
    u = np.cross(r, f)
    rel = v - cam[None, :]
    cx = rel @ r
    cy = rel @ u
    cz = rel @ f
    fl = 1.0 / math.tan(math.radians(fov) * 0.5)
    aspect = w / h
    ndc_x = (cx / np.maximum(cz, 1e-4)) * fl / aspect
    ndc_y = (cy / np.maximum(cz, 1e-4)) * fl
    sx = (ndc_x * 0.5 + 0.5) * w
    sy = (1.0 - (ndc_y * 0.5 + 0.5)) * h
    return sx, sy, cz


def render(parts, path, w=960, h=720, cam=None, target=None, bg=(0.90, 0.89, 0.88)):
    cam = np.array(cam if cam is not None else [2.6, 1.35, -2.35])
    target = np.array(target if target is not None else [0.0, 0.85, 0.15])
    up = np.array([0.0, 1.0, 0.0])
    lights = [
        (np.array([3.5, 4.5, -3.0]), np.array([1.0, 0.98, 0.94]), 1.15),
        (np.array([-2.5, 2.0, -1.5]), np.array([0.55, 0.62, 0.75]), 0.35),
        (np.array([0.5, 1.0, 3.5]), np.array([1.0, 0.85, 0.7]), 0.45),
    ]
    metals = {"steel": 0.92, "gold": 0.95, "hair": 0.08, "leather": 0.05}

    all_v = []
    all_f = []
    all_c = []
    all_m = []
    off = 0
    for name, mesh in parts.items():
        v = mesh.np_verts()
        f = mesh.np_faces()
        if len(v) == 0 or len(f) == 0:
            continue
        n = vertex_normals(v, f)
        alb = mesh.np_cols()
        col = shade_vertices(v, n, alb, metals[name], cam, lights)
        all_v.append(v)
        all_f.append(f + off)
        all_c.append(col)
        off += len(v)
        all_m.append(name)
    v = np.concatenate(all_v, 0)
    f = np.concatenate(all_f, 0)
    c = np.concatenate(all_c, 0)

    sx, sy, sz = project(v, cam, target, up, 38.0, w, h)
    tsx = np.stack([sx[f[:, 0]], sx[f[:, 1]], sx[f[:, 2]]], 1)
    tsy = np.stack([sy[f[:, 0]], sy[f[:, 1]], sy[f[:, 2]]], 1)
    tsz = np.stack([sz[f[:, 0]], sz[f[:, 1]], sz[f[:, 2]]], 1)
    cr = np.stack([c[f[:, 0], 0], c[f[:, 1], 0], c[f[:, 2], 0]], 1)
    cg = np.stack([c[f[:, 0], 1], c[f[:, 1], 1], c[f[:, 2], 1]], 1)
    cb = np.stack([c[f[:, 0], 2], c[f[:, 1], 2], c[f[:, 2], 2]], 1)

    zbuf = np.full((h, w), 1e9, np.float64)
    out = np.zeros((h, w, 3), np.float64)
    out[:, :] = np.array(bg)
    raster_gouraud(tsx, tsy, tsz, cr, cg, cb, zbuf, out, w, h)
    img = np.clip(out ** (1 / 1.05) * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(img).save(path)
    print("wrote", path, "tris", len(f), "verts", len(v))


# ---------------------------------------------------------------------------
# OBJ export
# ---------------------------------------------------------------------------


def export_obj(parts, path):
    mtl_path = os.path.splitext(path)[0] + ".mtl"
    mtl_name = os.path.basename(mtl_path)
    mats = {
        "steel": (STEEL, 0.9, 80),
        "gold": (GOLD, 0.95, 90),
        "hair": (RED, 0.05, 12),
        "leather": (LEATHER_C, 0.02, 8),
    }
    with open(mtl_path, "w") as m:
        for k, (kd, rs, ns) in mats.items():
            m.write(f"newmtl {k}\nKd {kd[0]:.4f} {kd[1]:.4f} {kd[2]:.4f}\n")
            m.write(f"Ks {rs:.3f} {rs:.3f} {rs:.3f}\nNs {ns}\n")
            tex = {"steel": "tex_steel.jpg", "gold": "tex_gold.jpg", "hair": "tex_hair.jpg"}.get(k)
            if tex:
                m.write(f"map_Kd {tex}\n")
            m.write("\n")
    with open(path, "w") as f:
        f.write(f"mtllib {mtl_name}\n")
        off = 1
        for name, mesh in parts.items():
            v = mesh.np_verts()
            uv = mesh.np_uvs()
            faces = mesh.np_faces()
            n = vertex_normals(v, faces) if len(v) else None
            f.write(f"o {name}\nusemtl {name}\n")
            for p in v:
                f.write(f"v {p[0]:.5f} {p[1]:.5f} {p[2]:.5f}\n")
            for t in uv:
                f.write(f"vt {t[0]:.5f} {t[1]:.5f}\n")
            if n is not None:
                for q in n:
                    f.write(f"vn {q[0]:.5f} {q[1]:.5f} {q[2]:.5f}\n")
            for a, b, c in faces:
                ia, ib, ic = a + off, b + off, c + off
                f.write(f"f {ia}/{ia}/{ia} {ib}/{ib}/{ib} {ic}/{ic}/{ic}\n")
            off += len(v)
    print("wrote", path)


# ---------------------------------------------------------------------------
# Compact Lua (EditableMesh) exporter
# ---------------------------------------------------------------------------


def pack_mesh(mesh: Mesh):
    v = mesh.np_verts().astype(np.float32)
    f = mesh.np_faces().astype(np.uint32)
    raw = struct.pack("<I", len(v)) + v.tobytes() + struct.pack("<I", len(f)) + f.tobytes()
    return zlib.compress(raw, 9)


def write_lua(parts, path):
    """Procedural-quality mesh baked into a command-bar EditableMesh script."""
    blobs = {k: pack_mesh(m) for k, m in parts.items() if m.faces}

    def b64(data):
        import base64

        return base64.b64encode(data).decode("ascii")

    colors = {
        "steel": (196, 200, 208, "Metal", 0.28),
        "gold": (212, 168, 58, "Foil", 0.4),
        "hair": (178, 18, 24, "SmoothPlastic", 0),
        "leather": (16, 14, 14, "SmoothPlastic", 0),
    }
    chunks = []
    for k, blob in blobs.items():
        s = b64(blob)
        # split for lua string limits
        parts_s = [s[i : i + 180] for i in range(0, len(s), 180)]
        lua_tbl = ",".join(f'"{p}"' for p in parts_s)
        chunks.append(f'["{k}"]={{{lua_tbl}}}')

    lua = f'''--[[
	Capacete Romano Centurião — malha profissional (EditableMesh)
	Cole na Command Bar do Roblox Studio.
]]
do
	local HttpService = game:GetService("HttpService")
	local AssetService = game:GetService("AssetService")
	local Selection = game:GetService("Selection")

	local B64 = {{ {", ".join(chunks)} }}
	local COL = {{
		steel = {{Color3.fromRGB(196,200,208), Enum.Material.Metal, 0.28}},
		gold = {{Color3.fromRGB(212,168,58), Enum.Material.Foil, 0.40}},
		hair = {{Color3.fromRGB(178,18,24), Enum.Material.SmoothPlastic, 0}},
		leather = {{Color3.fromRGB(16,14,14), Enum.Material.SmoothPlastic, 0}},
	}}

	local function b64decode(data)
		local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
		data = string.gsub(data, '[^'..b..'=]', '')
		return (data:gsub('.', function(x)
			if x == '=' then return '' end
			local r,f='', (b:find(x)-1)
			for i=6,1,-1 do r=r..(f%2^i - f%2^(i-1) > 0 and '1' or '0') end
			return r
		end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
			if #x ~= 8 then return '' end
			local c=0
			for i=1,8 do c=c + (x:sub(i,i)=='1' and 2^(8-i) or 0) end
			return string.char(c)
		end))
	end

	-- inflate via a tiny inflate (only if HttpService fails). We store UNCOMPRESSED if needed.
	-- Packed as raw little-endian after inflate.

	local function u32(s, o)
		local a,b,c,d = s:byte(o, o+3)
		return a + b*256 + c*65536 + d*16777216
	end
	local function f32(s, o)
		local a,b,c,d = s:byte(o, o+3)
		if not d then return 0 end
		local n = a + b*256 + c*65536 + d*16777216
		if n == 0 then return 0 end
		local sign = 1
		if n >= 2147483648 then sign = -1 n = n - 2147483648 end
		local exp = math.floor(n / 8388608)
		local mant = n % 8388608
		if exp == 0 then return sign * (mant / 8388608) * 2^(-126) end
		if exp == 255 then return sign * math.huge end
		return sign * (1 + mant/8388608) * 2^(exp-127)
	end

	local acc = Instance.new("Accessory")
	acc.Name = "CapaceteRomanoCenturiao"
	acc.AccessoryType = Enum.AccessoryType.Hat
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2,0.2,0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Anchored = true
	handle.Parent = acc
	local att = Instance.new("Attachment")
	att.Name = "HatAttachment"
	att.Position = Vector3.new(0, 0.6, 0)
	att.Parent = handle

	local function inflate(raw)
		-- try game:GetService if available; else identity
		return raw
	end

	-- NOTE: payload is zlib. Decode + inflate with a Lua inflate.
	local function decodePayload(arr)
		local s = table.concat(arr)
		local bin = b64decode(s)
		return bin
	end

	print("[Snow Hub] Construindo malha profissional...")
	print("[Snow Hub] Se EditableMesh falhar, importe o .obj em: capacete_romano/CapaceteRomano.obj")
	acc.Parent = workspace
	handle.Anchored = true
	Selection:Set({{acc}})
end
'''
    # The zlib inflate in pure Lua is painful. Better embed UNCOMPRESSED quantized verts
    # as numbers in a compact way, or embed a procedural builder.
    # We'll write a better lua below from Python numbers with quantization.
    write_lua_quantized(parts, path)
    print("wrote", path)


def write_lua_quantized(parts, path):
    """Quantize verts to int16 in bbox, dump as Lua string of little-endian, rebuild EditableMesh."""
    import base64

    def pack_part(mesh: Mesh):
        v = mesh.np_verts()
        f = mesh.np_faces()
        if len(v) == 0:
            return None
        vmin = v.min(0)
        vmax = v.max(0)
        ext = np.maximum(vmax - vmin, 1e-6)
        q = np.clip(np.round((v - vmin) / ext * 65535), 0, 65535).astype(np.uint16)
        # faces as uint16 (assume <65535 verts per part)
        if f.max() > 65535:
            raise RuntimeError("too many verts")
        ff = f.astype(np.uint16)
        payload = q.tobytes() + ff.tobytes()
        return {
            "n": len(v),
            "nf": len(f),
            "min": vmin.tolist(),
            "ext": ext.tolist(),
            "b64": base64.b64encode(payload).decode("ascii"),
        }

    packed = {k: pack_part(m) for k, m in parts.items()}
    packed = {k: v for k, v in packed.items() if v}

    def split_b64(s, n=200):
        chunks = [s[i : i + n] for i in range(0, len(s), n)]
        return "{" + ",".join(f'"{c}"' for c in chunks) + "}"

    blocks = []
    for k, p in packed.items():
        blocks.append(
            f'{k}={{n={p["n"]},nf={p["nf"]},'
            f'min=Vector3.new({p["min"][0]:.6f},{p["min"][1]:.6f},{p["min"][2]:.6f}),'
            f'ext=Vector3.new({p["ext"][0]:.6f},{p["ext"][1]:.6f},{p["ext"][2]:.6f}),'
            f'data={split_b64(p["b64"])}}}'
        )

    lua = r'''--[[
	Capacete Romano Centurião — malha 3D profissional (EditableMesh)
	Cole este script INTEIRO na Command Bar do Roblox Studio e aperte Enter.
	Se um Dummy R6 estiver selecionado, o capacete é equipado na cabeça.
]]
do
	local AssetService = game:GetService("AssetService")
	local Selection = game:GetService("Selection")
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	pcall(function() ChangeHistoryService:SetWaypoint("Antes Capacete Romano") end)

	local PACK = {
''' + ",\n".join(blocks) + r'''
	}

	local STYLE = {
		steel = {Color3.fromRGB(196,200,208), Enum.Material.Metal, 0.30},
		gold = {Color3.fromRGB(212,168,58), Enum.Material.Foil, 0.42},
		hair = {Color3.fromRGB(178,18,24), Enum.Material.SmoothPlastic, 0},
		leather = {Color3.fromRGB(16,14,14), Enum.Material.SmoothPlastic, 0},
	}

	local function b64decode(data)
		local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
		data = string.gsub(data, '[^'..b..'=]', '')
		return (data:gsub('.', function(x)
			if x == '=' then return '' end
			local r,f='',(b:find(x)-1)
			for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
			return r
		end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
			if #x ~= 8 then return '' end
			local c=0
			for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
			return string.char(c)
		end))
	end

	local function u16(s, o)
		local a,b = s:byte(o, o+1)
		return a + b*256
	end

	local acc = Instance.new("Accessory")
	acc.Name = "CapaceteRomanoCenturiao"
	pcall(function() acc.AccessoryType = Enum.AccessoryType.Hat end)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.25,0.25,0.25)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Anchored = true
	handle.Parent = acc
	local hatAtt = Instance.new("Attachment")
	hatAtt.Name = "HatAttachment"
	hatAtt.Position = Vector3.new(0, 0.6, 0)
	hatAtt.Parent = handle

	local function makeMesh(name, pack)
		local bin = b64decode(table.concat(pack.data))
		local em = AssetService:CreateEditableMesh()
		local ids = table.create(pack.n)
		local vmin, ext = pack.min, pack.ext
		for i = 1, pack.n do
			local o = (i-1)*6 + 1
			local qx, qy, qz = u16(bin, o), u16(bin, o+2), u16(bin, o+4)
			local p = Vector3.new(
				vmin.X + (qx/65535)*ext.X,
				vmin.Y + (qy/65535)*ext.Y,
				vmin.Z + (qz/65535)*ext.Z
			)
			ids[i] = em:AddVertex(p)
		end
		local fo = pack.n*6
		for i = 1, pack.nf do
			local o = fo + (i-1)*6 + 1
			local a, b, c = u16(bin, o)+1, u16(bin, o+2)+1, u16(bin, o+4)+1
			em:AddTriangle(ids[a], ids[b], ids[c])
		end
		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		mp.Name = "Mesh_" .. name
		local st = STYLE[name]
		mp.Color = st[1]
		mp.Material = st[2]
		mp.Reflectance = st[3]
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.Massless = true
		mp.Anchored = false
		mp.CastShadow = true
		mp.Parent = acc
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = mp
		w.Parent = mp
		-- Keep authored transform: mesh is already in head space. MeshPart pivot may shift.
		return mp
	end

	print("[Snow Hub] Gerando malha 3D do capacete...")
	local ok, err = pcall(function()
		for name, pack in pairs(PACK) do
			makeMesh(name, pack)
		end
	end)
	if not ok then
		warn("[Snow Hub] EditableMesh indisponível: "..tostring(err))
		warn("Importe CapaceteRomano.obj pelo Asset Manager (MeshPart) e solde no Handle.")
	end

	local function isR6(model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		local head = model:FindFirstChild("Head")
		if not (hum and head and head:IsA("BasePart")) then return false end
		if hum.RigType ~= Enum.HumanoidRigType.R6 then return false end
		return true, hum, head
	end
	local char, hum, head
	for _, obj in ipairs(Selection:Get()) do
		if obj:IsA("Model") then
			local a,b,c = isR6(obj)
			if a then char,hum,head=obj,b,c break end
		end
		local m = obj:FindFirstAncestorOfClass("Model")
		if m then
			local a,b,c = isR6(m)
			if a then char,hum,head=m,b,c break end
		end
	end
	if not char then
		for _, m in ipairs(workspace:GetDescendants()) do
			if m:IsA("Model") then
				local a,b,c = isR6(m)
				if a then char,hum,head=m,b,c break end
			end
		end
	end
	if char and head then
		if not head:FindFirstChild("HatAttachment") then
			local a = Instance.new("Attachment")
			a.Name = "HatAttachment"
			a.Position = Vector3.new(0,0.6,0)
			a.Parent = head
		end
		acc.Parent = char
		handle.CFrame = head.CFrame
		handle.Anchored = false
		local hw = Instance.new("WeldConstraint")
		hw.Part0 = head
		hw.Part1 = handle
		hw.Parent = handle
		print("[Snow Hub] Capacete equipado em "..char:GetFullName())
	else
		local cam = workspace.CurrentCamera
		local cf = cam and (cam.CFrame * CFrame.new(0,0,-8)) or CFrame.new(0,4,0)
		acc.Parent = workspace
		handle.CFrame = cf
		handle.Anchored = true
		print("[Snow Hub] Nenhum R6. Capacete na frente da câmera.")
	end
	pcall(function()
		ChangeHistoryService:SetWaypoint("Capacete Romano criado")
		Selection:Set({acc})
	end)
end
'''
    with open(path, "w", encoding="utf-8") as f:
        f.write(lua)
    print("lua bytes", os.path.getsize(path))


def load_tex(name):
    p = os.path.join(ROOT, name)
    if not os.path.isfile(p):
        return None
    return np.asarray(Image.open(p).convert("RGB"))


def main():
    steel_tex = load_tex("tex_steel.jpg")
    hair_tex = load_tex("tex_hair.jpg")
    gold_tex = load_tex("tex_gold.jpg")
    print("building helmet...")
    parts = build_helmet(steel_tex, hair_tex, gold_tex)
    for k, m in parts.items():
        print(k, "verts", len(m.verts), "faces", len(m.faces))
    export_obj(parts, os.path.join(OUT, "CapaceteRomano.obj"))
    render(
        parts,
        os.path.join(OUT, "preview_produto.jpg"),
        w=1100,
        h=800,
        cam=[4.6, 2.15, -3.4],
        target=[0.0, 0.95, 0.25],
        bg=(0.91, 0.90, 0.88),
    )
    render(
        parts,
        os.path.join(OUT, "preview_estudio.jpg"),
        w=1100,
        h=800,
        cam=[-4.4, 2.3, -3.6],
        target=[0.0, 0.9, 0.2],
        bg=(0.10, 0.10, 0.11),
    )
    write_lua_quantized(parts, os.path.join(OUT, "CapaceteRomano_R6_CommandBar.lua"))
    # copy lua to repo root too
    root_lua = os.path.join(os.path.dirname(OUT), "CapaceteRomano_R6_CommandBar.lua")
    with open(os.path.join(OUT, "CapaceteRomano_R6_CommandBar.lua"), "r", encoding="utf-8") as s:
        data = s.read()
    with open(root_lua, "w", encoding="utf-8") as t:
        t.write(data)
    print("done")


if __name__ == "__main__":
    main()
