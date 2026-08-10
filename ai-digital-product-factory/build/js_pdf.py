"""Dependency-free PDF writer used by the ``Build PDF Document`` Code node.

n8n Code nodes cannot ``require`` npm packages, so the product PDF is assembled
by hand. Only two page kinds are needed:

* text pages  - Helvetica (base-14 font, WinAnsi), automatic wrapping + paging
* image pages - JPEG embedded directly with /DCTDecode (no re-encoding at all)

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

    // ---- text page: wrap, then break into as many pages as needed ---------
    const titleSize = page.title_size || (page.cover ? 30 : 18);
    const lines = [];
    // A page whose lines arrived as a single string still typesets.
    const pageLines = Array.isArray(page.lines) ? page.lines
      : (page.lines ? [String(page.lines)] : []);
    for (const raw of pageLines) {
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
