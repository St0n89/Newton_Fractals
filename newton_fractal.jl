#!/usr/bin/env julia
# ================================================================
#   newton_fractal.jl — Newton fractals with ZERO packages
# ================================================================
#   Only Julia Base + Printf (a stdlib) is used. No Plots, no
#   Images, no Makie — because real nerds write their own BMP. 😎
#
#   HOW TO USE:
#     1. Edit f(z) below. Any complex function works.
#     2. julia newton_fractal.jl
#     3. Open newton_fractal.bmp. Done. 🎉
#
#   What the script does:
#     - finds the roots of f by letting Newton do the digging
#     - runs Newton's method for every single pixel
#     - colors each pixel by WHICH root it fell into (hue)
#       and by HOW HARD Newton had to work (brightness)
#     - hand-writes a 24-bit BMP file, byte by byte
# ================================================================

using Printf

# ----------------------------------------------------------------
# 1) YOUR FUNCTION — the only input you need to touch
# ----------------------------------------------------------------
f(z) = z^3 - 1                  # the classic 🌀 (three basins)
# f(z) = z^5 - 1                # flower power 🌸
# f(z) = z^4 + 2im*z^2 - 2      # spicy 🌶️
# f(z) = sin(z) - z             # Newton himself struggled here 🌊
# f(z) = z^6 + z^3 - 2          # go big or go home 🚀

# ----------------------------------------------------------------
# 2) picture settings
# ----------------------------------------------------------------
const W, H   = 800, 800         # image size in pixels
const XC, YC = 0.0, 0.0         # center of the complex-plane view
const SPAN   = 2.4              # half-width of the view
const MAXIT  = 50               # Newton iterations per pixel
const TOL    = 1e-8             # "close enough to a root" 🤷

# ----------------------------------------------------------------
# 3) Newton's method. f is analytic, so a tiny central difference
#    is plenty accurate as a derivative — no symbolics needed.
# ----------------------------------------------------------------
function dnum(fun, z)
    h = 1e-7
    return (fun(z + h) - fun(z - h)) / (2h)
end

function newton(fun, z0)
    z = ComplexF64(z0)
    for k in 1:MAXIT
        fz = fun(z)
        abs(fz) < TOL && return z, k, true
        df = dnum(fun, z)
        df == 0 && break                                    # flat as a pancake 🥞
        step = fz / df
        abs(step) > 1e3 && (step *= 1e3 / abs(step))        # no galactic teleports 🌌
        z -= step
        isfinite(abs(z)) || break
    end
    return z, MAXIT, false
end

# ----------------------------------------------------------------
# 4) root discovery — let Newton find them, then we name them
# ----------------------------------------------------------------
function discover_roots(fun)
    roots = ComplexF64[]
    grid = range(-SPAN, SPAN; length = 17)
    for re in grid, im in grid
        z, k, ok = newton(fun, complex(re, im))
        ok && !any(r -> abs(r - z) < 1e-6, roots) && push!(roots, z)
    end
    if isempty(roots)
        @printf("😱 Newton found no roots at all! (black picture incoming)\n")
    else
        @printf("🔮 Discovered %d root%s: %s\n", length(roots),
                length(roots) == 1 ? "" : "s",
                join([@sprintf("%.3f%+.3fi", real(r), imag(r)) for r in roots], ", "))
    end
    return roots
end

# ----------------------------------------------------------------
# 5) hand-rolled HSV → RGB (the "colormap library" is 10 lines)
# ----------------------------------------------------------------
function hsv2rgb(h, s, v)
    h  = mod(h, 1.0)
    i  = floor(Int, 6h) % 6
    fr = 6h - floor(6h)
    p = v * (1 - s)
    q = v * (1 - s * fr)
    t = v * (1 - s * (1 - fr))
    r, g, b = i == 0 ? (v, t, p) :
               i == 1 ? (q, v, p) :
               i == 2 ? (p, v, t) :
               i == 3 ? (p, q, v) :
               i == 4 ? (t, p, v) : (v, p, q)
    return round.(UInt8, 255 .* clamp.((r, g, b), 0.0, 1.0))
end

# ----------------------------------------------------------------
# 6) render: one Newton per pixel — hue = root, shade = effort
# ----------------------------------------------------------------
function render(fun)
    roots = discover_roots(fun)
    @printf("🎨 Painting %d×%d pixels of pure mathematical chaos...\n", W, H)
    img = fill((UInt8(0), UInt8(0), UInt8(0)), H, W)   # row 1 = top
    xs = range(XC - SPAN, XC + SPAN; length = W)
    ys = range(YC + SPAN, YC - SPAN; length = H)       # top row on top
    for j in 1:H
        for i in 1:W
            z, k, ok = newton(fun, complex(xs[i], ys[j]))
            if ok && !isempty(roots)
                idx = argmin(map(r -> abs(r - z), roots))
                hue = (idx - 1) * 0.6180339887498949         # golden angle ✨
                val = 1.0 - 0.55 * k / MAXIT                  # slow = darker
                img[j, i] = hsv2rgb(hue, 0.85, val)
            elseif ok
                img[j, i] = hsv2rgb(0.0, 0.0, 0.9)           # one lonely root
            else
                img[j, i] = (UInt8(10), UInt8(8), UInt8(24)) # the void 🕳️
            end
        end
        j % (H ÷ 20) == 0 &&
            @printf("   %3d%% done — the fractal is fractalling\n", round(Int, 100j / H))
    end
    return img
end

# ----------------------------------------------------------------
# 7) a BMP writer, because we refuse to install a plotting library
# ----------------------------------------------------------------
_le32!(buf, pos, v) = (buf[pos]   = UInt8(v & 0xff);
                       buf[pos+1] = UInt8((v >>> 8)  & 0xff);
                       buf[pos+2] = UInt8((v >>> 16) & 0xff);
                       buf[pos+3] = UInt8((v >>> 24) & 0xff))
_le16!(buf, pos, v) = (buf[pos] = UInt8(v & 0xff); buf[pos+1] = UInt8((v >>> 8) & 0xff))

function write_bmp(path, img)
    h, w = size(img)
    pad      = (4 - (3w) % 4) % 4
    datasize = (3w + pad) * h
    out = fill(0x00, 54 + datasize)
    # --- 14-byte file header ---
    out[1], out[2] = 0x42, 0x4d                       # "BM" (Byte Magic)
    _le32!(out, 3,  54 + datasize)                    # file size
    _le32!(out, 7,  0)                                # reserved
    _le32!(out, 11, 54)                               # pixel data offset
    # --- 40-byte BITMAPINFOHEADER ---
    _le32!(out, 15, 40)                               # header size
    _le32!(out, 19, w)
    _le32!(out, 23, h)
    _le16!(out, 27, 1)                                # color planes
    _le16!(out, 29, 24)                               # bits per pixel
    _le32!(out, 31, 0)                                # no compression
    _le32!(out, 35, datasize)
    _le32!(out, 39, 2835)                             # 72 dpi 🖨️
    _le32!(out, 43, 2835)
    _le32!(out, 47, 0)                                # palette colors
    _le32!(out, 51, 0)                                # "important" colors (lol)
    # --- pixels: bottom-up, BGR ---
    p = 55
    for row in h:-1:1
        for col in 1:w
            r, g, b = img[row, col]
            out[p] = b; out[p+1] = g; out[p+2] = r
            p += 3
        end
        p += pad
    end
    open(path, "w") do io
        write(io, out)
    end
end

# ----------------------------------------------------------------
# 8) main — where the magic is scheduled 🪄
# ----------------------------------------------------------------
function main()
    println("🌀 Newton Fractal Generator — stdlibs only, we're hardcore like that")
    @printf("   Region: re ∈ [%.2f, %.2f], im ∈ [%.2f, %.2f]\n",
            XC - SPAN, XC + SPAN, YC - SPAN, YC + SPAN)
    img  = render(f)
    path = "newton_fractal.bmp"
    write_bmp(path, img)
    @printf("💾 Wrote %s (%d bytes) — open it with any image viewer!\n",
            path, filesize(path))
    println("🤓 Fun fact: the darkest pixels are where Newton gave up and went home.")
end

main()
