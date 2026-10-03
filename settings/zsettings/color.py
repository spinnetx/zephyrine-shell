"""Цветовые утилиты (только stdlib): hex <-> sRGB <-> OKLab/OKLCH, гамут-клип,
якорная деривация (DESIGN §3.5), контраст WCAG, строка hsl.

Hex-строки — 6 символов, с '#' или без; результат функций *_to_hex — нижний
регистр без '#' (формат scheme.json), если не сказано иное.
"""
import math

__all__ = [
    "normalize_hex", "hex_to_rgb", "rgb_to_hex", "hex_to_oklab", "oklab_to_hex",
    "hex_to_oklch", "oklch_to_hex", "rgb_to_oklab", "oklab_to_linear",
    "oklab_to_oklch", "oklch_to_oklab", "in_gamut", "clip_oklch",
    "derive", "derive_oklch", "relative_luminance", "contrast",
    "hsl_string", "hex_to_hsl", "pick_on_color", "validate_accent",
    "AccentError", "round_half_up",
]

# --- базовые преобразования ------------------------------------------------


def round_half_up(x):
    return int(math.floor(x + 0.5))


def normalize_hex(h):
    """'#BB9AF7' / 'bb9af7' -> 'bb9af7'; ValueError для некорректного ввода."""
    if not isinstance(h, str):
        raise ValueError("hex must be a string: %r" % (h,))
    s = h.strip()
    if s.startswith("#"):
        s = s[1:]
    if len(s) != 6:
        raise ValueError("expected 6 hex digits: %r" % (h,))
    try:
        int(s, 16)
    except ValueError:
        raise ValueError("invalid hex: %r" % (h,)) from None
    return s.lower()


def hex_to_rgb(h):
    s = normalize_hex(h)
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def rgb_to_hex(rgb):
    r, g, b = (min(255, max(0, int(v))) for v in rgb)
    return "%02x%02x%02x" % (r, g, b)


def _to_linear(c):  # c: 0..1
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _from_linear(c):
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * (c ** (1 / 2.4)) - 0.055


def rgb_to_oklab(rgb):
    """rgb: 0..255 (int/float) -> (L, a, b)."""
    r, g, b = (_to_linear(v / 255.0) for v in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def oklab_to_linear(lab):
    """(L, a, b) -> линейный sRGB (r, g, b), может выходить за [0, 1]."""
    L, a, b = lab
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def oklab_to_oklch(lab):
    L, a, b = lab
    return (L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360.0)


def oklch_to_oklab(lch):
    L, C, H = lch
    h = math.radians(H)
    return (L, C * math.cos(h), C * math.sin(h))


def hex_to_oklab(h):
    return rgb_to_oklab(hex_to_rgb(h))


def hex_to_oklch(h):
    return oklab_to_oklch(hex_to_oklab(h))


_EPS = 1e-7


def in_gamut(lch_or_lab_lin):
    """Проверка по линейным компонентам sRGB."""
    return all(-_EPS <= v <= 1 + _EPS for v in lch_or_lab_lin)


def _lin_to_hex(lin):
    return rgb_to_hex(
        tuple(round_half_up(255 * _from_linear(min(1.0, max(0.0, v)))) for v in lin))


def oklab_to_hex(lab):
    """Округление half-up; без уменьшения хромы (простой clamp)."""
    return _lin_to_hex(oklab_to_linear(lab))


def clip_oklch(lch):
    """Уменьшает C бинарным поиском до попадания в гамут sRGB (L, H неизменны).
    L<=0 -> чёрный, L>=1 -> белый."""
    L, C, H = lch
    L = min(1.0, max(0.0, L))
    C = max(0.0, C)
    if L <= 0.0 or L >= 1.0:
        return (L, 0.0, H)
    if in_gamut(oklab_to_linear(oklch_to_oklab((L, C, H)))):
        return (L, C, H)
    lo, hi = 0.0, C
    for _ in range(40):
        mid = (lo + hi) / 2
        if in_gamut(oklab_to_linear(oklch_to_oklab((L, mid, H)))):
            lo = mid
        else:
            hi = mid
    return (L, lo, H)


def oklch_to_hex(lch):
    return oklab_to_hex(oklch_to_oklab(clip_oklch(lch)))


# --- якорная деривация (§3.5) ----------------------------------------------

_ACHROMATIC = 1e-4


def derive_oklch(k_lch, b_lch, new_b_lch):
    """Чистая формула §3.5 над тройками OKLCH; возвращает OKLCH (без клипа)."""
    LK, CK, HK = k_lch
    LB, CB, HB = b_lch
    LN, CN, HN = new_b_lch
    L = LN + (LK - LB)
    if CB < _ACHROMATIC:
        C, H = CK, HK
    else:
        C = CK * (CN / CB)
        # при ахроматичном новом якоре оттенок не определён — оставляем оттенок K
        H = HK if CN < _ACHROMATIC else (HN + (HK - HB)) % 360.0
    return (L, C, H)


def derive(k_literal, base_anchor, new_anchor):
    """Производный цвет K для якоря B.

    k_literal   — литерал K из scheme.json;
    base_anchor — базовое значение якоря (scheme.json);
    new_anchor  — эффективное значение якоря.
    Short-circuit: new == base -> возвращается k_literal как есть (без вычислений).
    """
    if normalize_hex(new_anchor) == normalize_hex(base_anchor):
        return k_literal
    res = derive_oklch(hex_to_oklch(k_literal), hex_to_oklch(base_anchor),
                       hex_to_oklch(new_anchor))
    return oklch_to_hex(res)


# --- контраст WCAG -----------------------------------------------------------


def relative_luminance(h):
    r, g, b = (_to_linear(v / 255.0) for v in hex_to_rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(h1, h2):
    a, b = relative_luminance(h1), relative_luminance(h2)
    if a < b:
        a, b = b, a
    return (a + 0.05) / (b + 0.05)


# --- HSL-строка --------------------------------------------------------------


def hex_to_hsl(h):
    """-> (H 0..360, S 0..100, L 0..100) float."""
    r, g, b = (v / 255.0 for v in hex_to_rgb(h))
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    d = mx - mn
    if d == 0:
        return (0.0, 0.0, l * 100)
    s = d / (1 - abs(2 * l - 1))
    if mx == r:
        hh = ((g - b) / d) % 6
    elif mx == g:
        hh = (b - r) / d + 2
    else:
        hh = (r - g) / d + 4
    return (hh * 60 % 360, s * 100, l * 100)


def hsl_string(h):
    """'bb9af7' -> '267, 85%, 78%' (целые, half-up)."""
    hh, s, l = hex_to_hsl(h)
    return "%d, %d%%, %d%%" % (round_half_up(hh) % 360, round_half_up(s), round_half_up(l))


# --- on-цвет и валидация акцента (§3.5) ------------------------------------


def pick_on_color(bg_hex, preferred=None, min_contrast=4.5):
    """Цвет текста на bg: preferred, если контраст достаточен; иначе тёмный
    (L=0.25) или светлый (L=0.95) вариант той же хромы/оттенка — лучший по контрасту."""
    if preferred is not None and contrast(preferred, bg_hex) >= min_contrast:
        return normalize_hex(preferred)
    _, C, H = hex_to_oklch(bg_hex)
    best = None
    for L in (0.25, 0.95):
        cand = oklch_to_hex((L, min(C, 0.08), H))
        if best is None or contrast(cand, bg_hex) > contrast(best, bg_hex):
            best = cand
    return best


LIGHT_MAX_L = 0.52   # светлота акцента на светлой теме (OKLCH): ярче — плохо читается на светлом фоне


def light_accent(accent, max_l=LIGHT_MAX_L):
    """Акцент для светлой темы: тот же оттенок и насыщенность, светлота не выше max_l (с клипом в гамут).
    Уже достаточно тёмный акцент возвращается без изменений."""
    accent = normalize_hex(accent)
    L, C, H = hex_to_oklch(accent)
    if L <= max_l:
        return accent
    return oklch_to_hex((max_l, C, H))


class AccentError(ValueError):
    pass


def validate_accent(accent, background, on_primary, min_l=0.55):
    """Возвращает (on_primary_итог, contrast_primary_bg, contrast_on_primary).
    AccentError с понятным текстом — если акцент недопустим."""
    L = hex_to_oklch(accent)[0]
    if L < min_l:
        raise AccentError(
            "акцент слишком тёмный для тёмной темы (OKLCH L=%.2f < %.2f)" % (L, min_l))
    cpb = contrast(accent, background)
    if cpb < 3.0:
        raise AccentError("контраст акцента к фону %.2f:1 < 3:1" % cpb)
    on = pick_on_color(accent, on_primary, 4.5)
    return on, cpb, contrast(on, accent)


def validate_accent_light(accent, background, on_primary):
    """То же для светлой темы (accent — уже приведённый `light_accent`): акцент не должен быть слишком светлым
    (контраст к светлому фону >= 3:1). -> (on_primary_итог, contrast_primary_bg, contrast_on_primary)."""
    cpb = contrast(accent, background)
    if cpb < 3.0:
        raise AccentError("контраст акцента к светлому фону %.2f:1 < 3:1" % cpb)
    on = pick_on_color(accent, on_primary, 4.5)
    return on, cpb, contrast(on, accent)
