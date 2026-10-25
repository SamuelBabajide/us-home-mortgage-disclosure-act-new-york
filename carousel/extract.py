"""Measure the rendered deck and emit a layout spec the PowerPoint build uses.

The PDF is produced by a browser from deck.html. Rebuilding the same design by
hand in PowerPoint would drift from it the first time either changed, so instead
this reads the finished layout out of the DOM: every box that paints a fill, and
every run of text with the position, size, weight and colour the browser gave it.
The .pptx is then assembled from those measurements, which makes it a faithful
copy of the PDF with real, editable text rather than a picture of it.

Also writes one background PNG per slide, with all content hidden, so the
photograph and its scrim come through exactly as rendered. PowerPoint cannot
draw the layered CSS gradients that produce them.
"""
import json
import pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path('/home/claude/work/carousel')
PX_PER_IN = 96          # the page is rendered at 960px for a 10in slide

JS = r"""
() => {
  const SKIP = new Set(['SCRIPT','STYLE','TITLE','META']);
  const slides = [...document.querySelectorAll('.slide')];

  const hex = c => {
    const m = c.match(/rgba?\(([^)]+)\)/); if (!m) return null;
    const p = m[1].split(',').map(s => parseFloat(s));
    const a = p.length > 3 ? p[3] : 1;
    if (a === 0) return null;
    return { hex: p.slice(0,3).map(v => Math.round(v).toString(16).padStart(2,'0')).join('').toUpperCase(),
             alpha: a };
  };

  // does this element lay its children out as blocks?
  const isBlocky = el => {
    const d = getComputedStyle(el).display;
    return d === 'block' || d === 'flex' || d === 'grid' || d === 'list-item' ||
           d === 'table' || d === 'table-row' || d === 'table-cell';
  };

  return slides.map((slide, si) => {
    const base = slide.getBoundingClientRect();
    const fills = [], texts = [];

    const walk = (el, suppressText) => {
      if (SKIP.has(el.tagName)) return;
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden') return;
      const r = el.getBoundingClientRect();
      if (r.width < 0.5 || r.height < 0.5) return;

      // a painted box: background fill, rounded or not
      const bg = hex(cs.backgroundColor);
      if (bg && el !== slide) {
        fills.push({ x:r.left-base.left, y:r.top-base.top, w:r.width, h:r.height,
                     color:bg.hex, alpha:bg.alpha,
                     radius: parseFloat(cs.borderTopLeftRadius) || 0 });
      }
      // a left border used as a rule (the tiles and the bullets)
      const blw = parseFloat(cs.borderLeftWidth) || 0;
      const blc = blw > 0 ? hex(cs.borderLeftColor) : null;
      if (blc) fills.push({ x:r.left-base.left, y:r.top-base.top, w:blw, h:r.height,
                            color:blc.hex, alpha:blc.alpha, radius:0 });
      // a top border used as a rule (the table's total row, the note, the footer)
      const btw = parseFloat(cs.borderTopWidth) || 0;
      const btc = btw > 0 ? hex(cs.borderTopColor) : null;
      if (btc) fills.push({ x:r.left-base.left, y:r.top-base.top, w:r.width, h:Math.max(btw,0.75),
                            color:btc.hex, alpha:btc.alpha, radius:0 });
      const bbw = parseFloat(cs.borderBottomWidth) || 0;
      const bbc = bbw > 0 ? hex(cs.borderBottomColor) : null;
      if (bbc) fills.push({ x:r.left-base.left, y:r.bottom-base.top-Math.max(bbw,0.75),
                            w:r.width, h:Math.max(bbw,0.75), color:bbc.hex, alpha:bbc.alpha, radius:0 });

      // text: emitted at the first ancestor whose children are all inline, so a
      // paragraph stays one box and its <b> runs keep their weight
      const kids = [...el.children];
      const ownText = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
      // Emit a box for this element's own inline content only. An element can
      // hold text AND a block child (a label with its count beneath it), so the
      // inline part is measured with a Range that stops at the first block
      // child; the block child then emits its own box when we recurse.
      const firstBlock = [...el.childNodes].findIndex(n => n.nodeType === 1 && isBlocky(n));
      let box = r;
      if (ownText && firstBlock > 0) {
        const rg = document.createRange();
        rg.setStart(el, 0); rg.setEnd(el, firstBlock);
        const rr = rg.getBoundingClientRect();
        if (rr.width > 0.5 && rr.height > 0.5) box = rr;
      }
      if (ownText && !suppressText) {
        const runs = [];
        const collect = (node, bold, size, color, italic) => {
          for (const n of node.childNodes) {
            if (n.nodeType === 3) {
              const t = n.textContent.replace(/\s+/g, ' ');
              if (t.trim()) runs.push({ text:t, bold, size, color, italic, br:false });
            } else if (n.nodeType === 1 && n.tagName === 'BR') {
              if (!runs.length || runs[runs.length - 1].br)
                runs.push({ text:' ', bold, size, color, italic, br:true });
              else runs[runs.length - 1].br = true;
            } else if (n.nodeType === 1 && !SKIP.has(n.tagName)) {
              if (isBlocky(n)) continue;   // its own box, emitted on recursion
              const s = getComputedStyle(n);
              collect(n, parseInt(s.fontWeight) >= 600, parseFloat(s.fontSize),
                      (hex(s.color)||{hex:'FFFFFF'}).hex, s.fontStyle === 'italic');
            }
          }
        };
        collect(el, parseInt(cs.fontWeight) >= 600, parseFloat(cs.fontSize),
                (hex(cs.color)||{hex:'FFFFFF'}).hex, cs.fontStyle === 'italic');
        if (runs.length) {
          const pt = parseFloat(cs.paddingTop) || 0, pb = parseFloat(cs.paddingBottom) || 0;
          const pl = parseFloat(cs.paddingLeft) || 0, pr = parseFloat(cs.paddingRight) || 0;
          texts.push({
            x:box.left-base.left+pl, y:box.top-base.top+pt,
            w:Math.max(box.width-pl-pr, 8), h:Math.max(box.height-pt-pb, 8),
            align: cs.textAlign === 'right' ? 'right' : cs.textAlign === 'center' ? 'center' : 'left',
            lineHeight: parseFloat(cs.lineHeight) / parseFloat(cs.fontSize) || 1.2,
            linePx: parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.2,
            spacing: parseFloat(cs.letterSpacing) || 0,
            upper: cs.textTransform === 'uppercase',
            href: (el.closest('a') || {}).href || null,
            runs });
        }
      }
      // a block child emits its own box; an inline one is already covered above
      kids.forEach(k => walk(k, isBlocky(k) ? false : true));
    };
    walk(slide, false);
    return { index: si + 1, fills, texts };
  });
}
"""

with sync_playwright() as pw:
    b = pw.chromium.launch()
    p = b.new_page(viewport={'width': 960, 'height': 960}, device_scale_factor=1.5)
    p.goto(f'file://{HERE}/deck.html')
    p.wait_for_timeout(800)

    spec = p.evaluate(JS)

    # backgrounds only: hide every child of every slide, keep ::before and the
    # layered background gradients
    p.add_style_tag(content='.slide > * { visibility: hidden !important }')
    p.wait_for_timeout(250)
    for i in range(len(spec)):
        p.locator('.slide').nth(i).screenshot(path=str(HERE / f'bg{i+1}.jpg'),
                                             type='jpeg', quality=88)
    b.close()

pathlib.Path(HERE / 'layout.json').write_text(json.dumps(spec))
print(f'{len(spec)} slides measured')
print(f'  fills {sum(len(s["fills"]) for s in spec)}, text boxes {sum(len(s["texts"]) for s in spec)}, '
      f'runs {sum(len(t["runs"]) for s in spec for t in s["texts"])}')
print(f'  backgrounds written: bg1..bg{len(spec)}.jpg')
