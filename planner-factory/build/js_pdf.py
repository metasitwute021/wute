"""Dependency-free PDF writer used by the ``Build PDF`` Code node.

n8n Code nodes cannot ``require`` npm packages, so the planner is assembled by
hand. Page kinds:

* text    - Helvetica (base-14 font, WinAnsi), automatic wrapping + paging
* image   - JPEG embedded directly with /DCTDecode (no re-encoding at all)
* month   - a real calendar grid for one month, computed from the weekday maths
* grid    - a ruled table: column headers over N empty rows (habit, budget, ...)
* lined   - a writing page, ruled or dotted

The last three exist because a language model cannot be trusted to lay out a
calendar. Ask one for February and it will hand back thirty days, or a Monday
that is really a Thursday. Geometry is code's job; the model only writes the
words that go around it.

Pages can also carry navigation: ``anchor`` names a destination, ``spec.tabs``
draws a clickable strip down the right edge of every page, and ``page.index``
renders a contents list whose rows jump to the page they name. Links are
resolved after every page exists, so a January tab on the cover works.

The JPEG-only rule is deliberate: a JPEG byte stream is a valid PDF image
stream as-is, while PNG would require inflating and re-filtering the pixel data.
That is why the image generation step asks OpenAI for ``output_format: jpeg``
for everything that ends up inside the PDF.
"""

PDF_LIB_JS = r"""
// ---------------------------------------------------------------------------
// Minimal PDF 1.4 writer (no external dependencies).
// ---------------------------------------------------------------------------
const PDF_FONT = { regular: 'F1', bold: 'F2' };

// Strip anything Helvetica/WinAnsi cannot show, then escape PDF string syntax.
function pdfEscape(text) {
  return String(text === undefined || text === null ? '' : text)
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/[–—]/g, '-')
    .replace(/…/g, '...')
    .replace(/[^\x20-\x7E\xA1-\xFF]/g, '')
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

// Read width/height/components out of a JPEG SOF marker.
function jpegInfo(buffer) {
  let i = 2;
  while (i < buffer.length - 9) {
    if (buffer[i] !== 0xff) { i += 1; continue; }
    const marker = buffer[i + 1];
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      i += 2;
      continue;
    }
    const length = buffer.readUInt16BE(i + 2);
    const isSOF = marker >= 0xc0 && marker <= 0xcf &&
      marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isSOF) {
      return {
        height: buffer.readUInt16BE(i + 5),
        width: buffer.readUInt16BE(i + 7),
        components: buffer[i + 9],
      };
    }
    i += 2 + length;
  }
  return { width: 1024, height: 1024, components: 3 };
}

// Greedy word wrap. Helvetica averages ~0.5em per character, which is accurate
// enough for body copy at 10-12pt.
function wrapText(text, fontSize, usableWidth) {
  const maxChars = Math.max(20, Math.floor(usableWidth / (fontSize * 0.5)));
  const out = [];
  for (const rawLine of String(text).split('\n')) {
    let line = '';
    for (const word of rawLine.split(/\s+/)) {
      if (!word) continue;
      if (!line.length) { line = word; continue; }
      if ((line + ' ' + word).length <= maxChars) { line += ' ' + word; }
      else { out.push(line); line = word; }
    }
    out.push(line);
  }
  return out;
}

// A field the model answered with a bare string still typesets as one line,
// and a missing one produces nothing rather than the word "undefined".
function asLines(value) {
  if (Array.isArray(value)) return value.map((v) => String(v === null || v === undefined ? '' : v));
  if (value === undefined || value === null || value === '') return [];
  return [String(value)];
}

// ---------------------------------------------------------------------------
// Calendar geometry. A language model cannot lay out February; Date can.
// ---------------------------------------------------------------------------
const WEEKDAYS_SUN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function weekdayHeaders(startsMonday) {
  return startsMonday
    ? WEEKDAYS_SUN.slice(1).concat(WEEKDAYS_SUN.slice(0, 1))
    : WEEKDAYS_SUN.slice();
}

// Returns six rows of seven cells. A dated planner gets real day numbers; an
// undated one gets empty boxes the buyer fills in, which is what makes the
// product evergreen instead of worthless every January.
function monthMatrix(year, month, startsMonday) {
  const rows = [[], [], [], [], [], []];
  if (!year) {
    for (const row of rows) { for (let i = 0; i < 7; i += 1) row.push(0); }
    return { rows, dated: false, days: 0 };
  }
  const days = new Date(Date.UTC(year, month, 0)).getUTCDate();
  let lead = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
  if (startsMonday) lead = (lead + 6) % 7;
  const cells = [];
  for (let i = 0; i < lead; i += 1) cells.push(null);
  for (let d = 1; d <= days; d += 1) cells.push(d);
  while (cells.length < 42) cells.push(null);
  for (let r = 0; r < 6; r += 1) rows[r] = cells.slice(r * 7, r * 7 + 7);
  return { rows, dated: true, days };
}

function buildPdf(spec) {
  const PW = spec.width || 595.28;   // A4 portrait by default
  const PH = spec.height || 841.89;
  const margin = spec.margin || 56;
  const bodySize = spec.body_size || 11;
  const leading = Math.round(bodySize * 1.5);

  // Clickable month/section tabs down the right edge. This is what separates a
  // $5 printable from a $20 digital planner: the file becomes something you
  // navigate rather than scroll. The strip steals width from the body column.
  const tabs = Array.isArray(spec.tabs)
    ? spec.tabs.filter((t) => t && t.anchor).slice(0, 16)
    : [];
  const TAB_W = tabs.length ? (spec.tab_width || 26) : 0;
  const usableWidth = PW - margin * 2 - TAB_W;
  const contentRight = PW - margin - TAB_W;

  // Object ids 1-5 are reserved: catalog, page tree, 2 fonts, document info.
  const objects = [null, null, null, null, null];
  const push = (content) => { objects.push(content); return objects.length; };
  const pageIds = [];

  // A link can point at a page that has not been written yet - a January tab
  // on the cover, say - so pages are reserved now and serialised at the end,
  // once every anchor has a page to resolve to.
  const pageMeta = [];
  const anchors = {};

  const addPage = (contentStream, extraResources) => {
    const contentId = push(
      `<< /Length ${Buffer.byteLength(contentStream, 'latin1')} >>\n` +
      `stream\n${contentStream}\nendstream`
    );
    const id = push('');
    pageIds.push(id);
    const meta = { id, contentId, resources: extraResources || null, links: [] };
    pageMeta.push(meta);
    return meta;
  };

  const footer = (label) => {
    if (!label) return '';
    return `BT /${PDF_FONT.regular} 8 Tf 0.45 0.45 0.45 rg ` +
      `${margin} ${(margin / 2).toFixed(2)} Td (${pdfEscape(label)}) Tj ET 0 0 0 rg\n`;
  };

  // Returns the drawing commands plus the link rectangles they imply. Links
  // are collected rather than attached because the page object does not exist
  // until its content stream has been measured.
  const tabStrip = (activeAnchor) => {
    if (!tabs.length) return { stream: '', links: [] };
    const top = PH - margin;
    const slot = (top - margin) / tabs.length;
    const height = Math.min(slot - 3, 96);
    const links = [];
    let stream = '';
    tabs.forEach((tab, index) => {
      const y = top - slot * index - height;
      const x = PW - TAB_W;
      const active = activeAnchor && tab.anchor === activeAnchor;
      const shade = active ? '0.25' : '0.88';
      stream += `${shade} ${shade} ${shade} rg ` +
        `${x.toFixed(2)} ${y.toFixed(2)} ${TAB_W.toFixed(2)} ${height.toFixed(2)} re f\n`;
      // A 90-degree text matrix so the label reads bottom-to-top in the tab.
      stream += `BT /${PDF_FONT.bold} 8 Tf ${active ? '1 1 1' : '0.2 0.2 0.2'} rg ` +
        `0 1 -1 0 ${(x + TAB_W / 2 + 3).toFixed(2)} ${(y + 7).toFixed(2)} Tm ` +
        `(${pdfEscape(String(tab.label || '').slice(0, 14))}) Tj ET 0 0 0 rg\n`;
      links.push({ anchor: tab.anchor, rect: [x, y, x + TAB_W, y + height] });
    });
    return { stream, links };
  };

  // ---- drawing primitives ------------------------------------------------
  const RULE = (shade) => `${shade} ${shade} ${shade} RG`;

  const line = (x1, y1, x2, y2, width, shade) =>
    `${width} w ${RULE(shade)} ${x1.toFixed(2)} ${y1.toFixed(2)} m ` +
    `${x2.toFixed(2)} ${y2.toFixed(2)} l S 0 0 0 RG\n`;

  const label = (text, x, y, size, font, shade) =>
    `BT /${font} ${size} Tf ${shade} ${shade} ${shade} rg ${x.toFixed(2)} ` +
    `${y.toFixed(2)} Td (${pdfEscape(text)}) Tj ET 0 0 0 rg\n`;

  // Right-aligned text needs the string's width, and Helvetica's real widths
  // are not uniform. 0.5em is the same approximation wrapText uses; a day
  // number is two characters, so the error is under a point.
  const labelRight = (text, x, y, size, font, shade) =>
    label(text, x - String(text).length * size * 0.5, y, size, font, shade);

  // A table drawn as lines, not as text: column rules, row rules, an optional
  // shaded header band. Everything with a grid on the page goes through here.
  // ``first_col_width`` widens column 0 for row labels. Without it a habit
  // called "Lights out by 11" ran straight through the column rule and into
  // Monday.
  const table = (x, y, w, h, cols, rows, opts) => {
    const options = opts || {};
    const firstW = options.first_col_width || 0;
    const colW = firstW ? (w - firstW) / Math.max(1, cols - 1) : w / cols;
    const colX = (index) => (firstW
      ? (index === 0 ? x : x + firstW + colW * (index - 1))
      : x + colW * index);
    const headerH = options.header_height || 0;
    const bodyY = y - headerH;
    const rowH = (h - headerH) / rows;
    let stream = '';

    if (headerH && options.header_shade !== undefined) {
      const s = options.header_shade;
      stream += `${s} ${s} ${s} rg ${x.toFixed(2)} ${bodyY.toFixed(2)} ` +
        `${w.toFixed(2)} ${headerH.toFixed(2)} re f\n`;
    }
    if (Array.isArray(options.headers)) {
      options.headers.forEach((text, index) => {
        stream += label(text, colX(index) + 6, bodyY + headerH / 2 - 3,
                        options.header_size || 8, PDF_FONT.bold, 0.25);
      });
    }
    for (let r = 0; r <= rows; r += 1) {
      const ly = bodyY - rowH * r;
      stream += line(x, ly, x + w, ly, 0.6, r === 0 ? 0.55 : 0.82);
    }
    if (headerH) stream += line(x, y, x + w, y, 0.6, 0.55);
    for (let c = 0; c <= cols; c += 1) {
      const lx = c === cols ? x + w : colX(c);
      stream += line(lx, y, lx, bodyY - rowH * rows, 0.6, 0.82);
    }
    return { stream, colW, rowH, bodyY, firstW: firstW || colW, colX };
  };

  // A table of contents whose rows jump to the page they name. Rows that do
  // not fit are counted, never quietly discarded: a contents list that stops
  // short is worse than none at all, and it is invisible unless someone looks
  // at the last page.
  let droppedRows = 0;
  const indexBlock = (entries, startY) => {
    const links = [];
    let stream = '';
    let y = startY;
    for (const entry of entries) {
      if (!entry || !entry.anchor) continue;
      if (y < margin + leading) { droppedRows += 1; continue; }
      stream += `BT /${PDF_FONT.regular} ${bodySize} Tf ${margin} ${y.toFixed(2)} Td ` +
        `(${pdfEscape(entry.label)}) Tj ET\n`;
      stream += `[1 3] 0 d 0.75 0.75 0.75 RG 0.6 w ` +
        `${(margin + 8).toFixed(2)} ${(y - 3).toFixed(2)} m ` +
        `${contentRight.toFixed(2)} ${(y - 3).toFixed(2)} l S [] 0 d 0 0 0 RG\n`;
      links.push({
        anchor: entry.anchor,
        rect: [margin - 4, y - 5, contentRight, y + bodySize + 2],
      });
      y -= leading * 1.7;
    }
    return { stream, links };
  };

  for (const page of spec.pages || []) {
    // An anchor names the first page emitted for this spec entry, so a link
    // lands on the section opener even when the section spills over.
    const anchorSlot = pageIds.length;
    if (page.anchor) anchors[page.anchor] = anchorSlot;

    // ---- image page: fit the JPEG inside the page, centred -----------------
    if (page.type === 'image' && page.jpeg_base64) {
      const data = Buffer.from(page.jpeg_base64, 'base64');
      const info = jpegInfo(data);
      const bleed = page.full_bleed ? 0 : margin / 2;
      // A full-bleed page keeps the whole sheet; anything else leaves the tab
      // gutter clear so the strip never sits on top of the artwork.
      const gutter = page.full_bleed ? 0 : TAB_W;
      const scale = Math.min(
        (PW - gutter - bleed * 2) / info.width,
        (PH - bleed * 2) / info.height
      );
      const w = info.width * scale;
      const h = info.height * scale;
      const x = (PW - gutter - w) / 2;
      const y = (PH - h) / 2;
      const imageId = push(Buffer.concat([
        Buffer.from(
          `<< /Type /XObject /Subtype /Image /Width ${info.width} /Height ${info.height}` +
          ` /ColorSpace ${info.components === 1 ? '/DeviceGray' : '/DeviceRGB'}` +
          ` /BitsPerComponent 8 /Filter /DCTDecode /Length ${data.length} >>\nstream\n`,
          'latin1'
        ),
        data,
        Buffer.from('\nendstream', 'latin1'),
      ]));
      let stream = `q ${w.toFixed(2)} 0 0 ${h.toFixed(2)} ${x.toFixed(2)} ${y.toFixed(2)} cm /Im0 Do Q\n`;
      if (page.caption) {
        stream += `BT /${PDF_FONT.regular} 10 Tf ${margin} ${(y - 18).toFixed(2)} Td ` +
          `(${pdfEscape(page.caption)}) Tj ET\n`;
      }
      stream += footer(page.footer);
      const strip = page.full_bleed ? { stream: '', links: [] } : tabStrip(page.anchor);
      const meta = addPage(stream + strip.stream, `/XObject << /Im0 ${imageId} 0 R >>`);
      for (const link of strip.links) meta.links.push(link);
      continue;
    }

    // ---- month page: calendar grid plus a side column ----------------------
    if (page.type === 'month') {
      const titleY = PH - margin - 22;
      let stream = label(page.title || 'Month', margin, titleY, 24, PDF_FONT.bold, 0);
      if (page.subtitle) {
        stream += label(page.subtitle, margin, titleY - 18, 10, PDF_FONT.regular, 0.4);
      }

      // The side column carries the writing prompts the model produced. The
      // calendar keeps whatever is left, so a longer prompt never squeezes a
      // week off the page - the split is fixed.
      const sideW = page.side_lines && page.side_lines.length ? 150 : 0;
      const gridW = contentRight - margin - (sideW ? sideW + 14 : 0);
      const gridTop = titleY - 40;
      const gridH = gridTop - margin - 18;

      const matrix = monthMatrix(
        page.year ? Number(page.year) : null,
        Number(page.month_number) || 1,
        page.week_starts_monday !== false
      );
      // A month that fits in five weeks gets five taller rows instead of a
      // blank strip along the bottom. Five is the floor so the twelve months
      // do not all have different-sized boxes.
      let weeks = matrix.rows.length;
      while (weeks > 5 && matrix.rows[weeks - 1].every((d) => !d)) weeks -= 1;

      const headers = weekdayHeaders(page.week_starts_monday !== false);
      const grid = table(margin, gridTop, gridW, gridH, 7, weeks, {
        headers, header_height: 18, header_shade: 0.93, header_size: 8,
      });
      stream += grid.stream;

      matrix.rows.slice(0, weeks).forEach((row, r) => {
        row.forEach((day, c) => {
          if (!day) return;
          stream += labelRight(String(day),
                               margin + grid.colW * (c + 1) - 5,
                               grid.bodyY - grid.rowH * r - 12,
                               9, PDF_FONT.regular, 0.35);
        });
      });

      if (sideW) {
        const sx = contentRight - sideW;
        let sy = gridTop;
        stream += label(page.side_title || 'This month', sx, sy, 10, PDF_FONT.bold, 0.2);
        sy -= 20;
        for (const raw of page.side_lines) {
          for (const wrapped of wrapText(raw, 9, sideW)) {
            if (sy < margin + 30) break;
            stream += label(wrapped, sx, sy, 9, PDF_FONT.regular, 0.35);
            sy -= 13;
          }
          // A ruled answer space under each prompt - the point of a planner.
          for (let i = 0; i < 2 && sy > margin + 24; i += 1) {
            sy -= 12;
            stream += line(sx, sy, sx + sideW, sy, 0.5, 0.85);
          }
          sy -= 12;
        }
      }

      stream += footer(page.footer);
      const strip = tabStrip(page.anchor);
      const meta = addPage(stream + strip.stream, null);
      for (const link of strip.links) meta.links.push(link);
      continue;
    }

    // ---- grid page: a ruled table with column headers ----------------------
    if (page.type === 'grid') {
      const titleY = PH - margin - 18;
      let stream = label(page.title || '', margin, titleY, 18, PDF_FONT.bold, 0);
      let top = titleY - 16;
      if (page.subtitle) {
        stream += label(page.subtitle, margin, top, 10, PDF_FONT.regular, 0.4);
        top -= 20;
      }
      for (const raw of asLines(page.lines)) {
        for (const wrapped of wrapText(raw, 10, contentRight - margin)) {
          stream += label(wrapped, margin, top, 10, PDF_FONT.regular, 0.3);
          top -= 15;
        }
      }
      top -= 10;

      const headers = Array.isArray(page.columns) ? page.columns : [];
      const rows = Math.max(1, Number(page.rows) || 12);
      const rowLabels = asLines(page.row_labels);
      const width = contentRight - margin;
      // A label column only needs to be wide when there are labels for it.
      const firstColW = rowLabels.length
        ? Math.min(170, Math.max(90, width * 0.28))
        : 0;
      const grid = table(margin, top, width, top - margin - 16,
                         Math.max(1, headers.length), rows, {
        headers, header_height: 20, header_shade: 0.93, header_size: 8,
        first_col_width: firstColW,
      });
      stream += grid.stream;

      // Row labels turn an empty table into a filled-in tracker: the model
      // supplies the habits, the writer supplies the boxes. Clipped to the
      // column it lives in rather than to a guessed character count.
      const labelSize = 8;
      const maxChars = Math.max(6, Math.floor((grid.firstW - 12) / (labelSize * 0.5)));
      rowLabels.forEach((text, index) => {
        if (index >= rows) return;
        stream += label(String(text).slice(0, maxChars), margin + 6,
                        grid.bodyY - grid.rowH * (index + 1) + grid.rowH / 2 - 3,
                        labelSize, PDF_FONT.regular, 0.3);
      });

      stream += footer(page.footer);
      const strip = tabStrip(page.anchor);
      const meta = addPage(stream + strip.stream, null);
      for (const link of strip.links) meta.links.push(link);
      continue;
    }

    // ---- lined page: prompts over ruled or dotted writing space ------------
    if (page.type === 'lined') {
      const titleY = PH - margin - 18;
      let stream = label(page.title || '', margin, titleY, 18, PDF_FONT.bold, 0);
      // The title needs air under it; without this the first prompt sat on
      // the title's baseline and read as a subtitle.
      let y = titleY - 30;
      if (page.subtitle) {
        stream += label(page.subtitle, margin, titleY - 16, 10, PDF_FONT.regular, 0.4);
        y = titleY - 44;
      }
      const spacing = Math.max(14, Number(page.spacing) || 26);
      const width = contentRight - margin;

      for (const prompt of asLines(page.lines)) {
        if (y < margin + spacing * 2) break;
        for (const wrapped of wrapText(prompt, 11, width)) {
          stream += label(wrapped, margin, y, 11, PDF_FONT.bold, 0.15);
          y -= 16;
        }
        const answerLines = Math.max(1, Number(page.lines_per_prompt) || 3);
        for (let i = 0; i < answerLines && y > margin + spacing; i += 1) {
          y -= spacing;
          stream += line(margin, y, margin + width, y, 0.5, 0.85);
        }
        y -= spacing * 0.6;
      }

      // Whatever is left becomes open writing space, ruled the same way, so a
      // short prompt list does not leave half a sheet of nothing.
      if (page.rule !== 'none') {
        while (y > margin + spacing) {
          y -= spacing;
          stream += line(margin, y, margin + width, y, 0.5, 0.9);
        }
      }

      stream += footer(page.footer);
      const strip = tabStrip(page.anchor);
      const meta = addPage(stream + strip.stream, null);
      for (const link of strip.links) meta.links.push(link);
      continue;
    }

    // ---- text page: wrap, then break into as many pages as needed ---------
    const titleSize = page.title_size || (page.cover ? 30 : 18);
    const lines = [];
    for (const raw of asLines(page.lines)) {
      for (const wrapped of wrapText(raw, bodySize, usableWidth)) lines.push(wrapped);
    }

    const firstTop = PH - margin - (page.title ? titleSize + 22 : 0);
    // A contents list eats into the first page's line budget, otherwise the
    // body copy under it would run off the bottom of the sheet.
    const indexRows = Array.isArray(page.index) ? page.index.length : 0;
    const indexHeight = indexRows ? indexRows * leading * 1.7 + leading : 0;
    const linesFirstPage = Math.max(
      1, Math.floor((firstTop - indexHeight - margin) / leading));
    const linesNextPage = Math.max(1, Math.floor((PH - margin * 2) / leading));

    let cursor = 0;
    let chunkIndex = 0;
    do {
      const capacity = chunkIndex === 0 ? linesFirstPage : linesNextPage;
      const chunk = lines.slice(cursor, cursor + capacity);
      cursor += capacity;

      let stream = '';
      if (page.title && chunkIndex === 0) {
        const titleY = PH - margin - titleSize;
        stream += `BT /${PDF_FONT.bold} ${titleSize} Tf ${margin} ${titleY.toFixed(2)} Td ` +
          `(${pdfEscape(page.title)}) Tj ET\n`;
        stream += `${margin} ${(titleY - 12).toFixed(2)} m ${contentRight.toFixed(2)} ` +
          `${(titleY - 12).toFixed(2)} l 0.7 w 0.8 0.8 0.8 RG S 0 0 0 RG\n`;
      }
      if (page.subtitle && chunkIndex === 0) {
        stream += `BT /${PDF_FONT.regular} 13 Tf 0.35 0.35 0.35 rg ${margin} ` +
          `${(PH - margin - titleSize - 34).toFixed(2)} Td (${pdfEscape(page.subtitle)}) Tj ET 0 0 0 rg\n`;
      }
      let startY = (chunkIndex === 0 ? firstTop : PH - margin) -
        (page.subtitle && chunkIndex === 0 ? 26 : 0);

      // A clickable contents list, drawn above the body copy on the first page.
      const pageLinks = [];
      if (chunkIndex === 0 && Array.isArray(page.index) && page.index.length) {
        // The subtitle sits only 14pt above the body baseline, which put the
        // first contents row hard against it. A row is a tap target, so it
        // gets a clear line of its own.
        if (page.subtitle) startY -= leading;
        const block = indexBlock(page.index, startY);
        stream += block.stream;
        for (const link of block.links) pageLinks.push(link);
        startY -= page.index.length * leading * 1.7 + leading;
      }

      if (chunk.length) {
        stream += `BT /${PDF_FONT.regular} ${bodySize} Tf ${leading} TL ` +
          `${margin} ${startY.toFixed(2)} Td\n`;
        for (const line of chunk) stream += `(${pdfEscape(line)}) Tj T*\n`;
        stream += 'ET\n';
      }
      stream += footer(page.footer);
      const strip = tabStrip(page.anchor);
      const meta = addPage(stream + strip.stream, null);
      for (const link of pageLinks) meta.links.push(link);
      for (const link of strip.links) meta.links.push(link);
      chunkIndex += 1;
    } while (cursor < lines.length);
  }

  if (!pageIds.length) {
    addPage(`BT /${PDF_FONT.regular} 12 Tf 56 780 Td (Empty document) Tj ET\n`, null);
  }

  // ---- resolve links, then serialise the reserved page objects ------------
  // A link whose anchor never appeared is dropped rather than pointing
  // somewhere arbitrary: a dead tab is worse than a plain one.
  let brokenLinks = 0;
  let linkCount = 0;
  for (const meta of pageMeta) {
    const annots = [];
    for (const link of meta.links) {
      const slot = anchors[link.anchor];
      if (slot === undefined || pageIds[slot] === undefined) { brokenLinks += 1; continue; }
      const [x1, y1, x2, y2] = link.rect;
      annots.push(push(
        `<< /Type /Annot /Subtype /Link /Border [0 0 0]` +
        ` /Rect [${x1.toFixed(2)} ${y1.toFixed(2)} ${x2.toFixed(2)} ${y2.toFixed(2)}]` +
        ` /Dest [${pageIds[slot]} 0 R /XYZ null null null] >>`
      ));
      linkCount += 1;
    }
    const resources =
      `/Font << /F1 3 0 R /F2 4 0 R >>` + (meta.resources ? ' ' + meta.resources : '');
    objects[meta.id - 1] =
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PW.toFixed(2)} ${PH.toFixed(2)}]` +
      ` /Resources << ${resources} >> /Contents ${meta.contentId} 0 R` +
      (annots.length ? ` /Annots [${annots.map((id) => `${id} 0 R`).join(' ')}]` : '') +
      ` >>`;
  }

  const info = spec.info || {};
  objects[0] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[1] = `<< /Type /Pages /Count ${pageIds.length} /Kids [` +
    pageIds.map((id) => `${id} 0 R`).join(' ') + '] >>';
  objects[2] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
  objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';
  objects[4] = '<< /Title (' + pdfEscape(info.title || 'Digital Product') + ')' +
    ' /Author (' + pdfEscape(info.author || 'AI Digital Product Factory') + ')' +
    ' /Subject (' + pdfEscape(info.subject || '') + ')' +
    ' /Keywords (' + pdfEscape(info.keywords || '') + ')' +
    ' /Creator (AI Digital Product Factory) /Producer (n8n) >>';

  // ---- serialise: header, objects, xref table, trailer --------------------
  const chunks = [];
  let offset = 0;
  const write = (value) => {
    const buf = Buffer.isBuffer(value) ? value : Buffer.from(String(value), 'latin1');
    chunks.push(buf);
    offset += buf.length;
  };

  write('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  const offsets = [];
  objects.forEach((obj, index) => {
    offsets[index] = offset;
    write(`${index + 1} 0 obj\n`);
    write(obj);
    write('\nendobj\n');
  });

  const xrefOffset = offset;
  write(`xref\n0 ${objects.length + 1}\n`);
  write('0000000000 65535 f \n');
  for (const o of offsets) write(`${String(o).padStart(10, '0')} 00000 n \n`);
  write(
    `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Info 5 0 R >>\n` +
    `startxref\n${xrefOffset}\n%%EOF\n`
  );

  return {
    buffer: Buffer.concat(chunks),
    page_count: pageIds.length,
    link_count: linkCount,
    broken_links: brokenLinks,
    dropped_index_rows: droppedRows,
  };
}
""".strip()
