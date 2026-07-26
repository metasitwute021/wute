"""Dependency-free PDF writer used by the ``Build PDF Document`` Code node.

n8n Code nodes cannot ``require`` npm packages, so the product PDF is assembled
by hand. Only two page kinds are needed:

* text pages  - Helvetica (base-14 font, WinAnsi), automatic wrapping + paging
* image pages - JPEG embedded directly with /DCTDecode (no re-encoding at all)

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
  const usableWidth = PW - margin * 2;

  // Object ids 1-5 are reserved: catalog, page tree, 2 fonts, document info.
  const objects = [null, null, null, null, null];
  const push = (content) => { objects.push(content); return objects.length; };
  const pageIds = [];

  const addPage = (contentStream, extraResources) => {
    const contentId = push(
      `<< /Length ${Buffer.byteLength(contentStream, 'latin1')} >>\n` +
      `stream\n${contentStream}\nendstream`
    );
    const resources =
      `/Font << /F1 3 0 R /F2 4 0 R >>` + (extraResources ? ' ' + extraResources : '');
    pageIds.push(push(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PW.toFixed(2)} ${PH.toFixed(2)}]` +
      ` /Resources << ${resources} >> /Contents ${contentId} 0 R >>`
    ));
  };

  const footer = (label) => {
    if (!label) return '';
    return `BT /${PDF_FONT.regular} 8 Tf 0.45 0.45 0.45 rg ` +
      `${margin} ${(margin / 2).toFixed(2)} Td (${pdfEscape(label)}) Tj ET 0 0 0 rg\n`;
  };

  for (const page of spec.pages || []) {
    // ---- image page: fit the JPEG inside the page, centred -----------------
    if (page.type === 'image' && page.jpeg_base64) {
      const data = Buffer.from(page.jpeg_base64, 'base64');
      const info = jpegInfo(data);
      const bleed = page.full_bleed ? 0 : margin / 2;
      const scale = Math.min(
        (PW - bleed * 2) / info.width,
        (PH - bleed * 2) / info.height
      );
      const w = info.width * scale;
      const h = info.height * scale;
      const x = (PW - w) / 2;
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
      addPage(stream, `/XObject << /Im0 ${imageId} 0 R >>`);
      continue;
    }

    // ---- text page: wrap, then break into as many pages as needed ---------
    const titleSize = page.title_size || (page.cover ? 30 : 18);
    const lines = [];
    for (const raw of page.lines || []) {
      for (const wrapped of wrapText(raw, bodySize, usableWidth)) lines.push(wrapped);
    }

    const firstTop = PH - margin - (page.title ? titleSize + 22 : 0);
    const linesFirstPage = Math.max(1, Math.floor((firstTop - margin) / leading));
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
        stream += `${margin} ${(titleY - 12).toFixed(2)} m ${(PW - margin).toFixed(2)} ` +
          `${(titleY - 12).toFixed(2)} l 0.7 w 0.8 0.8 0.8 RG S 0 0 0 RG\n`;
      }
      if (page.subtitle && chunkIndex === 0) {
        stream += `BT /${PDF_FONT.regular} 13 Tf 0.35 0.35 0.35 rg ${margin} ` +
          `${(PH - margin - titleSize - 34).toFixed(2)} Td (${pdfEscape(page.subtitle)}) Tj ET 0 0 0 rg\n`;
      }
      if (chunk.length) {
        const startY = (chunkIndex === 0 ? firstTop : PH - margin) -
          (page.subtitle && chunkIndex === 0 ? 26 : 0);
        stream += `BT /${PDF_FONT.regular} ${bodySize} Tf ${leading} TL ` +
          `${margin} ${startY.toFixed(2)} Td\n`;
        for (const line of chunk) stream += `(${pdfEscape(line)}) Tj T*\n`;
        stream += 'ET\n';
      }
      stream += footer(page.footer);
      addPage(stream, null);
      chunkIndex += 1;
    } while (cursor < lines.length);
  }

  if (!pageIds.length) {
    addPage(`BT /${PDF_FONT.regular} 12 Tf 56 780 Td (Empty document) Tj ET\n`, null);
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

  return { buffer: Buffer.concat(chunks), page_count: pageIds.length };
}
""".strip()
