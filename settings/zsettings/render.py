"""
Mini-template engine for Zephyrine settings.

Syntax: {{ path }} or {{ path | filter | filter:arg }}
No loops or conditions - only substitution and filtering.
"""

import re
import json
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, Union


class RenderError(Exception):
    """Error during template rendering."""
    pass


class TemplateRenderer:
    """Mini-template engine with filter support."""

    def __init__(self, context: Dict[str, Any]):
        """
        Initialize renderer with context.

        Context namespaces:
        - c.<key> — colors (hex like 'bb9af7' or '#bb9af7')
        - s.<key> — string derivatives (e.g., 's.primaryHsl' = "267, 85%, 78%")
        - a.<key> — alphas (numbers 0-1, e.g., 'a.glass' = 0.88)
        - r.<key> — radii (integers or floats, e.g., 'r.md' = 12)
        - f.<key> — fonts (family/size, e.g., 'f.shell.family', 'f.shell.size')
        - d.a.*, d.r.* — default alphas/radii (needed by the anchor filter)
        - hypr.*, idle.*, meta.* — other namespaced values
        """
        self.context = context
        self._current_path = None
        self._placeholder_pattern = re.compile(r'\{\{([^}]+)\}\}')

    def render(self, template: str) -> str:
        """
        Render template string by replacing all {{ ... }} placeholders.

        Args:
            template: Template string with {{ path | filter | ... }} syntax

        Returns:
            Rendered string

        Raises:
            RenderError: If placeholder or filter is unknown
        """
        def replace_placeholder(match):
            placeholder = match.group(1).strip()
            return self._process_placeholder(placeholder)

        result = self._placeholder_pattern.sub(replace_placeholder, template)

        # Verify no unprocessed placeholders remain
        if '{{' in result:
            raise RenderError(f"Unprocessed placeholder in output: {result}")

        return result

    def _process_placeholder(self, placeholder: str) -> str:
        """
        Process a single placeholder: path | filter | filter:arg

        Args:
            placeholder: Placeholder content (without {{ }})

        Returns:
            Filtered value as string

        Raises:
            RenderError: If path or filter is unknown
        """
        parts = placeholder.split('|')
        path = parts[0].strip()

        # Resolve the value from context
        value = self._resolve_path(path)
        self._current_path = path

        # Apply filters in sequence
        for i in range(1, len(parts)):
            filter_spec = parts[i].strip()
            value = self._apply_filter(value, filter_spec)

        return str(value)

    def _resolve_path(self, path: str) -> Any:
        """
        Resolve a dotted path from context.

        Args:
            path: Dotted path like 'c.primary' or 'a.glass'

        Returns:
            Value from context

        Raises:
            RenderError: If path not found
        """
        keys = path.split('.')
        current = self.context

        for key in keys:
            if isinstance(current, dict):
                if key not in current:
                    raise RenderError(f"Unknown key in path: {path}")
                current = current[key]
            else:
                raise RenderError(f"Cannot access key '{key}' on non-dict value in path: {path}")

        return current

    def _apply_filter(self, value: Any, filter_spec: str) -> Any:
        """
        Apply a single filter to a value.

        Args:
            value: Value to filter
            filter_spec: Filter specification like 'hex' or 'num:2' or 'rgba:0.88'

        Returns:
            Filtered value

        Raises:
            RenderError: If filter is unknown or invalid
        """
        if ':' in filter_spec:
            filter_name, arg = filter_spec.split(':', 1)
            filter_name = filter_name.strip()
            arg = arg.strip()
        else:
            filter_name = filter_spec
            arg = None

        # Normalize value to string for hex operations
        value_str = str(value).strip()

        if filter_name == 'hex':
            return self._filter_hex(value_str)
        elif filter_name == 'bare':
            return self._filter_bare(value_str)
        elif filter_name == 'hexa':
            if arg is None:
                raise RenderError("hexa filter requires argument (alpha hex or key)")
            return self._filter_hexa(value_str, arg)
        elif filter_name == 'argb':
            if arg is None:
                raise RenderError("argb filter requires argument (alpha hex or key)")
            return self._filter_argb(value_str, arg)
        elif filter_name == 'rgb':
            return self._filter_rgb(value_str)
        elif filter_name == 'rgba':
            if arg is None:
                raise RenderError("rgba filter requires argument (alpha value or key)")
            return self._filter_rgba(value_str, arg)
        elif filter_name == 'hyprrgba':
            if arg is None:
                raise RenderError("hyprrgba filter requires argument (alpha hex or key)")
            return self._filter_hyprrgba(value_str, arg)
        elif filter_name == 'hexbyte':
            return self._filter_hexbyte(value)
        elif filter_name == 'anchor':
            if arg is None:
                raise RenderError("anchor filter requires argument (anchor value or key)")
            return self._filter_anchor(value, arg)
        elif filter_name == 'num':
            if arg is None:
                raise RenderError("num filter requires argument (decimal places)")
            return self._filter_num(value, arg)
        elif filter_name == 'px':
            return self._filter_px(value_str)
        elif filter_name == 'lua_str':
            return self._filter_lua_str(value_str)
        elif filter_name == 'json_str':
            return self._filter_json_str(value_str)
        elif filter_name == 'css_str':
            return self._filter_css_str(value_str)
        else:
            raise RenderError(f"Unknown filter: {filter_name}")

    def _filter_hex(self, value: str) -> str:
        """Convert color to #rrggbb format."""
        value = value.lstrip('#').lower()
        if len(value) != 6:
            raise RenderError(f"Invalid hex color for hex filter: {value}")
        return f"#{value}"

    def _filter_bare(self, value: str) -> str:
        """Return hex color without # prefix."""
        value = value.lstrip('#').lower()
        if len(value) != 6:
            raise RenderError(f"Invalid hex color for bare filter: {value}")
        return value

    def _filter_hexa(self, color: str, alpha_arg: str) -> str:
        """Convert color to #rrggbbAA format."""
        color = color.lstrip('#').lower()
        if len(color) != 6:
            raise RenderError(f"Invalid hex color for hexa filter: {color}")

        alpha_hex = self._resolve_alpha_arg(alpha_arg)
        return f"#{color}{alpha_hex}"

    def _filter_argb(self, color: str, alpha_arg: str) -> str:
        """Convert color to #AArr ggbb format (ARGB)."""
        color = color.lstrip('#').lower()
        if len(color) != 6:
            raise RenderError(f"Invalid hex color for argb filter: {color}")

        alpha_hex = self._resolve_alpha_arg(alpha_arg)
        return f"#{alpha_hex}{color}"

    def _filter_rgb(self, value: str) -> str:
        """Convert #rrggbb to decimal RGB: 'r, g, b'."""
        color = value.lstrip('#').lower()
        if len(color) != 6:
            raise RenderError(f"Invalid hex color for rgb filter: {color}")

        r = int(color[0:2], 16)
        g = int(color[2:4], 16)
        b = int(color[4:6], 16)
        return f"{r}, {g}, {b}"

    def _filter_rgba(self, value: str, alpha_arg: str) -> str:
        """Convert color to rgba(r, g, b, a) format."""
        color = value.lstrip('#').lower()
        if len(color) != 6:
            raise RenderError(f"Invalid hex color for rgba filter: {color}")

        r = int(color[0:2], 16)
        g = int(color[2:4], 16)
        b = int(color[4:6], 16)

        # Resolve alpha value
        try:
            alpha = float(alpha_arg)
            if not (0 <= alpha <= 1):
                raise ValueError
        except (ValueError, TypeError):
            # Try to resolve from context
            alpha = self._resolve_path(alpha_arg)
            alpha = float(alpha)

        return f"rgba({r}, {g}, {b}, {alpha})"

    def _filter_hyprrgba(self, color: str, alpha_arg: str) -> str:
        """Convert to Hyprland format: rgba(rrggbbAA)."""
        color = color.lstrip('#').lower()
        if len(color) != 6:
            raise RenderError(f"Invalid hex color for hyprrgba filter: {color}")

        alpha_hex = self._resolve_alpha_arg(alpha_arg)
        return f"rgba({color}{alpha_hex})"

    def _filter_hexbyte(self, value: Any) -> str:
        """Convert alpha (0-1) to hex byte (00-ff)."""
        try:
            alpha = float(value)
        except (ValueError, TypeError):
            # Try to resolve from context
            alpha = float(self._resolve_path(str(value)))

        if not (0 <= alpha <= 1):
            raise RenderError(f"Alpha value out of range [0, 1]: {alpha}")

        # Round to nearest integer and convert to hex
        byte_val = int(round(alpha * 255))
        return f"{byte_val:02x}"

    def _filter_anchor(self, value: Any, anchor_arg: str) -> str:
        """
        Anchor filter for alphas and radii (DESIGN 3.3).

        `{{ a.glass | anchor:0.72 }}`: base = current value of the path, default = the same
        path in the `d` namespace (context['d'], mirrors a.* / r.*).
        Default base -> literal as written; otherwise L + (base - default), clipped to
        [0, 1] for a.* or [0, inf) for r.*, with as many decimals as the literal has.
        """
        path = self._current_path or ''
        ns = path.split('.', 1)[0]
        if ns not in ('a', 'r'):
            raise RenderError(f"anchor filter works only on a.* and r.* paths, got: {path!r}")
        literal = anchor_arg.strip()
        try:
            lit = Decimal(literal)
            base = Decimal(str(value).strip())
        except InvalidOperation:
            raise RenderError(f"anchor: non-numeric literal or value: {literal!r}, {value!r}")
        dpath = 'd.' + path
        try:
            default = Decimal(str(self._resolve_path(dpath)).strip())
        except (RenderError, InvalidOperation):
            raise RenderError(f"anchor filter needs default value in context at {dpath}")
        if base == default:
            return literal
        places = max(0, -lit.as_tuple().exponent)
        result = lit + (base - default)
        result = max(result, Decimal(0))
        if ns == 'a':
            result = min(result, Decimal(1))
        return f"{result:.{places}f}"

    def _filter_num(self, value: Any, decimal_places_arg: str) -> str:
        """Format number with specified decimal places."""
        try:
            places = int(decimal_places_arg)
        except (ValueError, TypeError):
            raise RenderError(f"Invalid decimal places for num filter: {decimal_places_arg}")

        try:
            num = float(value)
        except (ValueError, TypeError):
            raise RenderError(f"Cannot format non-numeric value with num filter: {value}")

        return f"{num:.{places}f}"

    def _filter_px(self, value: str) -> str:
        """Add 'px' suffix to value."""
        return f"{value}px"

    def _filter_lua_str(self, value: str) -> str:
        """Escape string for Lua."""
        # In Lua, we need to escape backslashes and quotes
        value = value.replace('\\', '\\\\')
        value = value.replace('"', '\\"')
        return f'"{value}"'

    def _filter_json_str(self, value: str) -> str:
        """Escape string for JSON (using json module)."""
        return json.dumps(value)

    def _filter_css_str(self, value: str) -> str:
        """Escape string for CSS."""
        # In CSS, main concerns are quotes and newlines
        value = value.replace('\\', '\\\\')
        value = value.replace('"', '\\"')
        value = value.replace('\n', '\\n')
        value = value.replace('\r', '\\r')
        return f'"{value}"'

    def _resolve_alpha_arg(self, arg: str) -> str:
        """
        Resolve alpha argument which can be:
        - Direct hex value: 'ee', 'AA'
        - Path to alpha key: 'a.glass' -> converts to hex
        - Path to hexbyte result: treated as hex directly
        """
        # Try as hex first (simple case)
        arg = arg.strip()
        if len(arg) == 2 and all(c in '0123456789abcdefABCDEF' for c in arg):
            return arg.lower()

        # Try as path
        try:
            value = self._resolve_path(arg)
            # If it's a float (alpha), convert to hex
            if isinstance(value, (int, float)):
                alpha = float(value)
                byte_val = int(round(alpha * 255))
                return f"{byte_val:02x}"
            # Otherwise use as-is (might be hex string)
            return str(value).lower()
        except RenderError:
            raise RenderError(f"Cannot resolve alpha argument: {arg}")


def render(template: str, context: Dict[str, Any]) -> str:
    """
    Render a template string with given context.

    Convenience function wrapping TemplateRenderer.

    Args:
        template: Template string with {{ path | filter }} syntax
        context: Context dictionary with values

    Returns:
        Rendered string

    Raises:
        RenderError: If template contains unknown keys or filters
    """
    renderer = TemplateRenderer(context)
    return renderer.render(template)
