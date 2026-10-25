/* Assemble the PowerPoint from the measured layout.
 *
 * Every slide is the rendered background (photograph plus its scrim, which
 * PowerPoint cannot draw) with the fills and text placed back on top as real
 * shapes and real text boxes. Positions come from layout.json, which was read
 * out of the browser, so the deck matches the PDF rather than approximating it,
 * and every word stays editable.
 */
const pptxgen = require('pptxgenjs');
const fs = require('fs');
const path = require('path');

const HERE = '/home/claude/work/carousel';
const spec = JSON.parse(fs.readFileSync(path.join(HERE, 'layout.json'), 'utf8'));

const PX = 96;                 // 960px render = 10in slide
const px = v => v / PX;        // px -> inches
const pt = v => v * 0.75;      // css px -> points

const pres = new pptxgen();
pres.defineLayout({ name: 'HMDA_SQUARE', width: 10, height: 10 });
pres.layout = 'HMDA_SQUARE';
pres.author = 'Samuel Babajide';
pres.title = 'Mortgage lending in New York';
pres.subject = 'HMDA Loan Application Register, New York State, 2022 to 2025';

for (const s of spec) {
  const slide = pres.addSlide();
  slide.background = { path: path.join(HERE, `bg${s.index}.jpg`) };

  // fills first, so text always sits on top of its card
  for (const f of s.fills) {
    const o = {
      x: px(f.x), y: px(f.y), w: px(f.w), h: px(f.h),
      fill: { color: f.color },
      line: { type: 'none' },
    };
    if (f.alpha < 1) o.fill.transparency = Math.round((1 - f.alpha) * 100);
    if (f.radius > 0.5) {
      // rectRadius is a fraction of the shorter side, and only on ROUNDED_RECTANGLE
      o.rectRadius = Math.min(0.5, f.radius / Math.min(f.w, f.h));
      slide.addShape(pres.ShapeType.roundRect, o);
    } else {
      slide.addShape(pres.ShapeType.rect, o);
    }
  }

  for (const t of s.texts) {
    const runs = t.runs.map((r, i) => {
      const ro = {
        fontSize: pt(r.size), bold: r.bold, italic: r.italic,
        color: r.color, fontFace: 'Arial',
        charSpacing: t.spacing ? pt(t.spacing) : undefined,
        breakLine: r.br === true,
      };
      // a hyperlink is a run property in pptxgenjs; on the shape it writes an
      // r:id it never declares and PowerPoint calls the file corrupt
      if (t.href) { ro.hyperlink = { url: t.href }; ro.underline = { style: 'none' }; }
      return { text: t.upper ? r.text.toUpperCase() : r.text, options: ro };
    });
    const o = {
      x: px(t.x), y: px(t.y) - 0.035, w: px(t.w) + 0.03, h: px(t.h) + 0.07,
      align: t.align, valign: 'top',
      margin: 0, isTextBox: true, wrap: true, shrinkText: false,
      lineSpacing: pt(t.linePx),
    };
    slide.addText(runs, o);
  }
}

pres.writeFile({ fileName: path.join(HERE, 'mortgage-lending-in-new-york.pptx') })
  .then(f => console.log('wrote', f));
