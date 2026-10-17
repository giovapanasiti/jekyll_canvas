// HTML (from the contenteditable block) -> Markdown for one paragraph/heading block.
import TurndownService from 'turndown';

const td = new TurndownService({
  headingStyle: 'atx',
  emDelimiter: '*',
  strongDelimiter: '**',
  codeBlockStyle: 'fenced',
  bulletListMarker: '-',
});

const IAL_SAME_LINE = /\s*\{[:#.][^}]*\}\s*$/;
const IAL_OWN_LINE = /\n\{:[^}]*\}\s*$/;

export function htmlToMarkdown(html, block) {
  // contenteditable leaves trailing <br> and non-breaking spaces behind
  const clean = html.replace(/(<br\s*\/?>\s*)+$/i, '').replace(/&nbsp;/g, ' ').replace(/\u00a0/g, ' ');
  let md = td.turndown(clean).trim();
  const original = block.markdown;

  if (block.type === 'header') {
    md = md.replace(/\s*\n\s*/g, ' ');
    const prefix = (original.match(/^\s{0,3}(#{1,6})\s/) || [])[1] || '#'.repeat(block.header_level || 1);
    const ial = (original.match(IAL_SAME_LINE) || [''])[0].trim();
    return `${prefix} ${md}${ial ? ' ' + ial : ''}`;
  }
  const ial = (original.match(IAL_OWN_LINE) || [''])[0];
  return md + ial.trimEnd();
}
