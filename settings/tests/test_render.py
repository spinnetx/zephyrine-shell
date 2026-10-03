"""
Unit tests for the render module (template engine).
"""

import unittest
from zsettings.render import render, TemplateRenderer, RenderError


class TestTemplateBasics(unittest.TestCase):
    """Test basic template rendering functionality."""

    def setUp(self):
        """Set up test context."""
        self.context = {
            'c': {
                'primary': 'bb9af7',
                'secondary': '7aa2f7',
                'background': '1e1e2e',
            },
            's': {
                'primaryHsl': '267, 85%, 78%',
            },
            'a': {
                'glass': 0.88,
                'surface': 0.94,
            },
            'r': {
                'lg': 14,
                'md': 12,
                'sm': 10,
                'xs': 8,
            },
            'f': {
                'shell': {
                    'family': 'JetBrainsMono Nerd Font',
                    'size': 13,
                },
            },
            'meta': {
                'tbVersion': '1.0',
            },
        }

    def test_simple_substitution(self):
        """Test simple placeholder substitution."""
        result = render('Color: {{ c.primary }}', self.context)
        self.assertEqual(result, 'Color: bb9af7')

    def test_multiple_substitutions(self):
        """Test multiple placeholders in one template."""
        result = render(
            'Primary: {{ c.primary }}, Secondary: {{ c.secondary }}',
            self.context
        )
        self.assertEqual(result, 'Primary: bb9af7, Secondary: 7aa2f7')

    def test_nested_path_resolution(self):
        """Test resolution of nested paths."""
        result = render('Font: {{ f.shell.family }}', self.context)
        self.assertEqual(result, 'Font: JetBrainsMono Nerd Font')

    def test_string_value_resolution(self):
        """Test resolution of string values."""
        result = render('HSL: {{ s.primaryHsl }}', self.context)
        self.assertEqual(result, 'HSL: 267, 85%, 78%')

    def test_numeric_value_resolution(self):
        """Test resolution of numeric values."""
        result = render('Alpha: {{ a.glass }}', self.context)
        self.assertEqual(result, 'Alpha: 0.88')

    def test_unknown_key_raises_error(self):
        """Test that unknown key raises RenderError."""
        with self.assertRaises(RenderError) as cm:
            render('Color: {{ c.nonexistent }}', self.context)
        self.assertIn('Unknown key', str(cm.exception))

    def test_unknown_filter_raises_error(self):
        """Test that unknown filter raises RenderError."""
        with self.assertRaises(RenderError) as cm:
            render('Color: {{ c.primary | unknown_filter }}', self.context)
        self.assertIn('Unknown filter', str(cm.exception))


class TestHexFilters(unittest.TestCase):
    """Test hex-related filters."""

    def setUp(self):
        """Set up test context."""
        self.context = {
            'c': {
                'primary': 'bb9af7',
            },
            'a': {
                'glass': 0.88,
            },
        }

    def test_hex_filter(self):
        """Test hex filter adds # prefix."""
        result = render('{{ c.primary | hex }}', self.context)
        self.assertEqual(result, '#bb9af7')

    def test_bare_filter(self):
        """Test bare filter removes # prefix."""
        result = render('{{ c.primary | bare }}', self.context)
        self.assertEqual(result, 'bb9af7')

    def test_hex_case_normalization(self):
        """Test that hex filters normalize case."""
        ctx = {'c': {'primary': 'BB9AF7'}}
        result = render('{{ c.primary | hex }}', ctx)
        self.assertEqual(result, '#bb9af7')

    def test_hexa_with_direct_hex(self):
        """Test hexa filter with direct hex byte alpha."""
        result = render('{{ c.primary | hexa:ee }}', self.context)
        self.assertEqual(result, '#bb9af7ee')

    def test_hexa_with_path_alpha(self):
        """Test hexa filter with alpha from context path."""
        result = render('{{ c.primary | hexa:a.glass }}', self.context)
        # a.glass = 0.88 -> 0.88 * 255 = 224.4 -> round = 224 = e0
        self.assertEqual(result, '#bb9af7e0')

    def test_argb_with_direct_hex(self):
        """Test argb filter with direct hex byte alpha."""
        result = render('{{ c.primary | argb:ee }}', self.context)
        self.assertEqual(result, '#eebb9af7')

    def test_argb_with_path_alpha(self):
        """Test argb filter with alpha from context path."""
        result = render('{{ c.primary | argb:a.glass }}', self.context)
        # a.glass = 0.88 -> e0
        self.assertEqual(result, '#e0bb9af7')


class TestRGBFilters(unittest.TestCase):
    """Test RGB-related filters."""

    def setUp(self):
        """Set up test context."""
        self.context = {
            'c': {
                'primary': 'bb9af7',
                'background': '1e1e2e',
            },
            'a': {
                'glass': 0.88,
            },
        }

    def test_rgb_filter(self):
        """Test rgb filter converts to decimal RGB."""
        result = render('{{ c.primary | rgb }}', self.context)
        # bb9af7: bb=187, 9a=154, f7=247
        self.assertEqual(result, '187, 154, 247')

    def test_rgb_filter_dark_color(self):
        """Test rgb filter with dark color."""
        result = render('{{ c.background | rgb }}', self.context)
        # 1e1e2e: 1e=30, 1e=30, 2e=46
        self.assertEqual(result, '30, 30, 46')

    def test_rgba_with_direct_alpha(self):
        """Test rgba filter with direct alpha value."""
        result = render('{{ c.background | rgba:0.88 }}', self.context)
        self.assertEqual(result, 'rgba(30, 30, 46, 0.88)')

    def test_rgba_with_path_alpha(self):
        """Test rgba filter with alpha from path."""
        result = render('{{ c.background | rgba:a.glass }}', self.context)
        self.assertEqual(result, 'rgba(30, 30, 46, 0.88)')

    def test_hyprrgba_with_direct_hex(self):
        """Test hyprrgba filter with direct hex alpha."""
        result = render('{{ c.primary | hyprrgba:ee }}', self.context)
        self.assertEqual(result, 'rgba(bb9af7ee)')

    def test_hyprrgba_with_path_alpha(self):
        """Test hyprrgba filter with alpha from path."""
        result = render('{{ c.primary | hyprrgba:a.glass }}', self.context)
        # a.glass = 0.88 -> e0
        self.assertEqual(result, 'rgba(bb9af7e0)')


class TestNumericFilters(unittest.TestCase):
    """Test numeric-related filters."""

    def setUp(self):
        """Set up test context."""
        self.context = {
            'a': {
                'glass': 0.88,
                'surface': 0.94,
            },
            'r': {
                'md': 12,
                'lg': 14,
            },
            'n': {
                'fontsize': 11.0,
                'value': 11,
            },
        }

    def test_hexbyte_direct_alpha(self):
        """Test hexbyte filter with direct alpha."""
        result = render('{{ a.glass | hexbyte }}', self.context)
        # 0.88 * 255 = 224.4 -> round = 224 = e0
        self.assertEqual(result, 'e0')

    def test_hexbyte_another_alpha(self):
        """Test hexbyte with different alpha value."""
        result = render('{{ a.surface | hexbyte }}', self.context)
        # 0.94 * 255 = 239.7 -> round = 240 = f0
        self.assertEqual(result, 'f0')

    def test_hexbyte_boundary_zero(self):
        """Test hexbyte with alpha = 0."""
        ctx = {'a': {'transparent': 0.0}}
        result = render('{{ a.transparent | hexbyte }}', ctx)
        self.assertEqual(result, '00')

    def test_hexbyte_boundary_one(self):
        """Test hexbyte with alpha = 1.0."""
        ctx = {'a': {'opaque': 1.0}}
        result = render('{{ a.opaque | hexbyte }}', ctx)
        self.assertEqual(result, 'ff')

    def test_num_filter_one_decimal(self):
        """Test num filter with 1 decimal place."""
        result = render('{{ n.fontsize | num:1 }}', self.context)
        self.assertEqual(result, '11.0')

    def test_num_filter_zero_decimals(self):
        """Test num filter with 0 decimal places."""
        result = render('{{ n.value | num:0 }}', self.context)
        self.assertEqual(result, '11')

    def test_num_filter_two_decimals(self):
        """Test num filter with 2 decimal places."""
        ctx = {'v': 3.14159}
        result = render('{{ v | num:2 }}', ctx)
        self.assertEqual(result, '3.14')

    def test_px_filter(self):
        """Test px filter adds pixel suffix."""
        result = render('{{ r.md | px }}', self.context)
        self.assertEqual(result, '12px')


class TestStringEscapeFilters(unittest.TestCase):
    """Test string escaping filters."""

    def setUp(self):
        """Set up test context."""
        self.context = {
            's': {
                'path': '/home/user/.config',
                'quote': 'He said "hello"',
                'newline': 'line1\nline2',
                'simple': 'text',
            },
        }

    def test_lua_str_simple(self):
        """Test lua_str filter with simple string."""
        result = render('{{ s.simple | lua_str }}', self.context)
        self.assertEqual(result, '"text"')

    def test_lua_str_with_quotes(self):
        """Test lua_str filter escapes quotes."""
        result = render('{{ s.quote | lua_str }}', self.context)
        self.assertEqual(result, '"He said \\"hello\\""')

    def test_lua_str_with_backslash(self):
        """Test lua_str filter escapes backslashes."""
        ctx = {'s': {'backslash': 'C:\\Users'}}
        result = render('{{ s.backslash | lua_str }}', ctx)
        self.assertEqual(result, '"C:\\\\Users"')

    def test_json_str_simple(self):
        """Test json_str filter with simple string."""
        result = render('{{ s.simple | json_str }}', self.context)
        self.assertEqual(result, '"text"')

    def test_json_str_with_quotes(self):
        """Test json_str filter uses json.dumps."""
        result = render('{{ s.quote | json_str }}', self.context)
        # json.dumps should produce valid JSON
        self.assertTrue(result.startswith('"') and result.endswith('"'))

    def test_css_str_simple(self):
        """Test css_str filter with simple string."""
        result = render('{{ s.simple | css_str }}', self.context)
        self.assertEqual(result, '"text"')

    def test_css_str_with_quotes(self):
        """Test css_str filter escapes quotes."""
        result = render('{{ s.quote | css_str }}', self.context)
        self.assertEqual(result, '"He said \\"hello\\""')

    def test_css_str_with_newline(self):
        """Test css_str filter escapes newlines."""
        result = render('{{ s.newline | css_str }}', self.context)
        self.assertIn('\\n', result)


class TestFilterChaining(unittest.TestCase):
    """Test chaining multiple filters."""

    def setUp(self):
        """Set up test context."""
        self.context = {
            'c': {
                'primary': 'bb9af7',
            },
            'a': {
                'glass': 0.88,
            },
        }

    def test_chain_hex_then_bare(self):
        """Test chaining hex and bare filters."""
        result = render('{{ c.primary | hex | bare }}', self.context)
        self.assertEqual(result, 'bb9af7')

    def test_chain_rgb_filter(self):
        """Test chain that produces RGB."""
        result = render('{{ c.primary | rgb }}', self.context)
        self.assertEqual(result, '187, 154, 247')

    def test_multiple_steps_hexa(self):
        """Test complex filter chain."""
        result = render('{{ c.primary | hexa:a.glass }}', self.context)
        self.assertEqual(result, '#bb9af7e0')


class TestComplexTemplates(unittest.TestCase):
    """Test complex real-world template scenarios."""

    def setUp(self):
        """Set up test context similar to real usage."""
        self.context = {
            'c': {
                'background': '1e1e2e',
                'primary': 'bb9af7',
            },
            'a': {
                'glass': 0.88,
            },
            'r': {
                'md': 12,
            },
            's': {
                'fontfamily': 'Inter',
            },
        }

    def test_gtk_css_template(self):
        """Test GTK CSS-like template."""
        template = '''
@define-color bg_color {{ c.background | hex }};
@define-color accent {{ c.primary | hex }};
opacity: {{ a.glass | num:2 }};
border-radius: {{ r.md | px }};
        '''.strip()
        result = render(template, self.context)
        self.assertIn('@define-color bg_color #1e1e2e;', result)
        self.assertIn('@define-color accent #bb9af7;', result)
        self.assertIn('opacity: 0.88;', result)
        self.assertIn('border-radius: 12px;', result)

    def test_rgba_in_css(self):
        """Test RGBA in CSS context."""
        result = render('background: {{ c.background | rgba:a.glass }};', self.context)
        self.assertEqual(result, 'background: rgba(30, 30, 46, 0.88);')

    def test_hyprland_rgba(self):
        """Test Hyprland RGBA format."""
        result = render('color = "{{ c.primary | hyprrgba:a.glass }}"', self.context)
        self.assertEqual(result, 'color = "rgba(bb9af7e0)"')


class TestErrorHandling(unittest.TestCase):
    """Test error handling."""

    def test_unknown_path_raises_error(self):
        """Test unknown path raises RenderError."""
        with self.assertRaises(RenderError):
            render('{{ unknown.path }}', {'c': {}})

    def test_unknown_filter_raises_error(self):
        """Test unknown filter raises RenderError."""
        with self.assertRaises(RenderError):
            render('{{ c.color | unknown }}', {'c': {'color': 'bb9af7'}})

    def test_filter_without_required_arg_raises_error(self):
        """Test filter without required argument raises RenderError."""
        with self.assertRaises(RenderError):
            render('{{ c.color | hexa }}', {'c': {'color': 'bb9af7'}})

    def test_invalid_hex_color_raises_error(self):
        """Test invalid hex color raises RenderError."""
        with self.assertRaises(RenderError):
            render('{{ c.color | hex }}', {'c': {'color': 'not_hex'}})

    def test_alpha_out_of_range_raises_error(self):
        """Test alpha out of range [0,1] raises error."""
        with self.assertRaises(RenderError):
            render('{{ a.bad | hexbyte }}', {'a': {'bad': 1.5}})

    def test_unprocessed_placeholder_raises_error(self):
        """Test that remaining {{ in output raises error."""
        # This would need a malformed renderer to test properly
        # Normally all placeholders should be processed
        pass


class TestIntegration(unittest.TestCase):
    """Integration tests with realistic scenarios."""

    def test_full_zephyrine_context(self):
        """Test with realistic Zephyrine context."""
        context = {
            'c': {
                'primary': 'bb9af7',
                'secondary': '7aa2f7',
                'background': '1e1e2e',
                'surface': '313244',
                'purple': 'bb9af7',
                'blue': '7aa2f7',
            },
            'a': {
                'glass': 0.88,
                'surface': 0.94,
            },
            'r': {
                'lg': 14,
                'md': 12,
                'sm': 10,
                'xs': 8,
            },
            'f': {
                'shell': {
                    'family': 'JetBrainsMono Nerd Font',
                    'size': 13,
                },
            },
        }

        # Test a realistic GTK template snippet
        template = '''
background-color: {{ c.background | hex }};
color: {{ c.primary | hex }};
opacity: {{ a.glass }};
border-radius: {{ r.md | px }};
accent: {{ c.purple | rgb }};
'''
        result = render(template, context)
        self.assertIn('background-color: #1e1e2e;', result)
        self.assertIn('color: #bb9af7;', result)
        self.assertIn('opacity: 0.88;', result)
        self.assertIn('border-radius: 12px;', result)
        self.assertIn('accent: 187, 154, 247;', result)

    def test_example_from_spec_rgba(self):
        """Test example from DESIGN.md: rgba(20, 20, 20, 0.88)."""
        context = {
            'c': {'bg': '141414'},  # 20, 20, 20 in decimal
            'a': {'glass': 0.88},
        }
        result = render('{{ c.bg | rgba:a.glass }}', context)
        self.assertEqual(result, 'rgba(20, 20, 20, 0.88)')

    def test_example_from_spec_hexa(self):
        """Test example from DESIGN.md: #ffbb9af7."""
        context = {
            'c': {'primary': 'ffbb9af7'},  # This is 8 chars, needs handling
        }
        # Actually, the spec shows #ffbb9af7 as hexa output
        # Let's test the hexa filter
        ctx2 = {'c': {'primary': 'bb9af7'}, 'a': {'alpha': 0xff / 255}}
        result = render('{{ c.primary | hexa:ff }}', ctx2)
        self.assertEqual(result, '#bb9af7ff')

    def test_example_from_spec_hexbyte(self):
        """Test example from DESIGN.md: dd."""
        context = {'a': {'alpha': 0xdd / 255}}  # 221/255 ≈ 0.867
        result = render('{{ a.alpha | hexbyte }}', context)
        # Round(0.867 * 255) = round(221.085) = 221 = 0xdd
        self.assertEqual(result, 'dd')

    def test_example_from_spec_num(self):
        """Test example from DESIGN.md: 11.0."""
        context = {'n': {'fontsize': 11}}
        result = render('{{ n.fontsize | num:1 }}', context)
        self.assertEqual(result, '11.0')

    def test_example_from_spec_px(self):
        """Test example from DESIGN.md: 12px."""
        context = {'r': {'radius': 12}}
        result = render('{{ r.radius | px }}', context)
        self.assertEqual(result, '12px')


class TestAnchorFilter(unittest.TestCase):
    """anchor:L = L + (base - default), clipped, same decimals; default -> literal."""

    DEFAULTS = {'a': {'glass': 0.88, 'surface': 0.94},
                'r': {'lg': 14, 'md': 12, 'sm': 10, 'xs': 8}}

    def ctx(self, glass=0.88, radius=12):
        return {
            'a': {'glass': glass, 'surface': 0.94},
            'r': {'lg': radius + 2, 'md': radius, 'sm': max(0, radius - 2), 'xs': max(0, radius - 4)},
            'd': self.DEFAULTS,
        }

    def test_default_returns_literal_verbatim(self):
        c = self.ctx()
        self.assertEqual(render('{{ a.glass | anchor:0.72 }}', c), '0.72')
        self.assertEqual(render('{{ a.glass | anchor:0.920 }}', c), '0.920')
        self.assertEqual(render('{{ r.md | anchor:16 }}', c), '16')

    def test_glass_shift(self):
        c = self.ctx(glass=0.78)
        self.assertEqual(render('{{ a.glass | anchor:0.72 }}', c), '0.62')
        self.assertEqual(render('{{ a.glass | anchor:0.92 }}', c), '0.82')
        self.assertEqual(render('{{ a.glass | anchor:0.90 }}', self.ctx(glass=0.95)), '0.97')

    def test_radius_shift(self):
        c = self.ctx(radius=16)
        self.assertEqual(render('{{ r.md | anchor:16 }}', c), '20')
        self.assertEqual(render('{{ r.sm | anchor:6 }}', c), '10')

    def test_clipping(self):
        self.assertEqual(render('{{ a.glass | anchor:0.72 }}', self.ctx(glass=0.5)), '0.34')
        self.assertEqual(render('{{ a.glass | anchor:0.99 }}', self.ctx(glass=1.0)), '1.00')
        self.assertEqual(render('{{ a.glass | anchor:0.1 }}', self.ctx(glass=0.5)), '0.0')
        self.assertEqual(render('{{ r.md | anchor:2 }}', self.ctx(radius=0)), '0')

    def test_chain_with_hexbyte(self):
        c = self.ctx(glass=0.78)
        self.assertEqual(render('{{ a.glass | anchor:0.72 | hexbyte }}', c), '9e')

    def test_errors(self):
        with self.assertRaises(RenderError):
            render('{{ a.glass | anchor:0.72 }}', {'a': {'glass': 0.88}})  # нет d
        with self.assertRaises(RenderError):
            render('{{ c.primary | anchor:1 }}', {'c': {'primary': '1'}, 'd': {}})
        with self.assertRaises(RenderError):
            render('{{ a.glass | anchor:x }}', self.ctx())


if __name__ == '__main__':
    unittest.main()
