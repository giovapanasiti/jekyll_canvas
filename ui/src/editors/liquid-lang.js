// Liquid + HTML for CodeMirror, with a fix for @codemirror/lang-liquid 6.3.3: its
// comment/raw tokenizers don't recognise the whitespace-control form `{%- endcomment -%}`,
// so everything after a `{%- comment -%}` was highlighted as a comment.
import { LanguageSupport } from '@codemirror/language';
import { html } from '@codemirror/lang-html';
import { liquidLanguage, liquidCompletionSource, closePercentBrace } from '@codemirror/lang-liquid';
import { ExternalTokenizer } from '@lezer/lr';

// Token ids from the generated grammar (lang-liquid dist/index.js).
const endrawTagStart = 4, rawText = 184, endcommentTagStart = 5, commentText = 185;

const isWordChar = (c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

function rawTokenizer(endTag, text, tagStart) {
  return new ExternalTokenizer((input) => {
    const start = input.pos;
    for (;;) {
      const { next } = input;
      if (next === 123 /* { */ && input.peek(1) === 37 /* % */) {
        let scan = 2;
        let size = 2;
        if (input.peek(scan) === 45 /* - */) size = ++scan;
        while (input.peek(scan) === 32 || input.peek(scan) === 10) scan++;
        let word = '';
        for (let c = input.peek(scan); isWordChar(c); c = input.peek(++scan)) word += String.fromCharCode(c);
        if (word === endTag) {
          if (input.pos > start) break;
          input.acceptToken(tagStart, size);
          break;
        }
      } else if (next < 0) {
        break;
      }
      input.advance();
      if (next === 10) break;
    }
    if (input.pos > start) input.acceptToken(text);
  });
}

// lang-liquid builds its parser with tokenizers [base, raw, comment, inlineComment, …].
const [, rawTok, commentTok] = liquidLanguage.parser.tokenizers;
const fixedLanguage = liquidLanguage.configure({
  tokenizers: [
    { from: rawTok, to: rawTokenizer('endraw', rawText, endrawTagStart) },
    { from: commentTok, to: rawTokenizer('endcomment', commentText, endcommentTagStart) },
  ],
});

export function liquidHtml() {
  const base = html();
  return new LanguageSupport(fixedLanguage, [
    base.support,
    fixedLanguage.data.of({ autocomplete: liquidCompletionSource() }),
    base.language.data.of({ closeBrackets: { brackets: ['{'] } }),
    closePercentBrace,
  ]);
}
