#!/usr/bin/env python3
"""Check the public publication boundary, SEO metadata and local site links."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json
import sys

SITE = Path(__file__).resolve().parents[1] / 'website'
ORIGIN = 'https://uniboard-dxm.pages.dev'

class Page(HTMLParser):
    def __init__(self):
        super().__init__(); self.h1 = 0; self.title = False; self.description = False
        self.canonical = None; self.links = []; self.json = None; self.json_text = ''
    def handle_starttag(self, tag, attributes):
        a = dict(attributes)
        if tag == 'h1': self.h1 += 1
        if tag == 'title': self.title = True
        if tag == 'meta' and a.get('name') == 'description': self.description = bool(a.get('content'))
        if tag == 'link' and a.get('rel') == 'canonical': self.canonical = a.get('href')
        if tag in ('a', 'link', 'img'):
            value = a.get('src') or a.get('href')
            if value: self.links.append(value)
        if tag == 'script':
            assert a.get('type') == 'application/ld+json', 'No tracking or executable scripts permitted'
            self.json = True
    def handle_data(self, data):
        if self.json: self.json_text += data
    def handle_endtag(self, tag):
        if tag == 'script' and self.json:
            schema = json.loads(self.json_text)
            assert schema['@context'] == 'https://schema.org'
            assert schema.get('@type') == 'MobileApplication'
            self.json = False; self.json_text = ''

for file in SITE.rglob('*'):
    assert not file.is_symlink(), f'Public site contains symlink: {file}'
    assert file.suffix not in ('.rb', '.py', '.p8', '.pem', '.key'), f'Private/source file in public site: {file}'
    if file.suffix != '.html': continue
    content = file.read_text()
    assert 'PUBLIC_SUPPORT_CONTACT' not in content, 'Public support contact is unset'
    page = Page(); page.feed(content)
    assert page.h1 == 1 and page.title, f'Page title or single H1 missing: {file}'
    if file.name != '404.html':
        expected = ORIGIN + '/' + str(file.parent.relative_to(SITE)).replace('.', '')
        expected = expected.rstrip('/') + '/'
        assert page.description and page.canonical == expected, f'Missing/wrong SEO metadata: {file}'
    for link in page.links:
        uri = urlsplit(link)
        if uri.scheme or uri.netloc or not uri.path: continue
        target = SITE / unquote(uri.path.lstrip('/')) if uri.path.startswith('/') else file.parent / unquote(uri.path)
        assert target.resolve().is_relative_to(SITE.resolve()), f'Link escapes public site: {file}'
        if target.is_dir(): target /= 'index.html'
        assert target.exists(), f'Missing local link or asset in {file}: {link}'
assert 'mailto:' in (SITE / 'support/index.html').read_text(), 'Support email is missing'
print('Website validated: public assets only, truthful structured data, canonical URLs and local links.')
