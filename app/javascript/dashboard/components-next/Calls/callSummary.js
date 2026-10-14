import { isCallNote } from 'dashboard/composables/useCallNotes';

/**
 * The AI's post-call summary, in the one shape the call sheet draws:
 * `{ fields: [{ kind, label, text }], body, footer, technical: [{ key, value }] }`.
 * `text`, `body` and `footer` are markdown, rendered by MessageFormatter.
 *
 * It has two sources. The voice bridge posts it as a private note when the
 * session is finalized (pathorsAI/pathors `buildCallNote`, chatwoot/call-note.ts):
 *
 *   📞 **通話摘要**（AI 生成）            ← or 📞 **通話記錄** when there is none
 *   **意圖**：… / **結果**：… / **待辦**：… / ⚠️ **警示**：…
 *   ---
 *   ⏱ 3 分 12 秒 · completed / 🔗 [完整逐字稿與錄音](…)
 *   ---
 *   **Agent 自訂欄位** / - roomName: … (the agent's variables, plumbing included)
 *   ---
 *   **逐字稿** / …
 *
 * The call's own `summary` (Pathors::CallSummary: intent, result, todos,
 * warnings, text) is the structured alternative a Pathors backend may send
 * with the call update; it is used when there is no note.
 */

// The bridge's two headers; no note a person writes in the sheet starts so.
export const CALL_SUMMARY_NOTE_PREFIXES = Object.freeze([
  '📞 **通話摘要**',
  '📞 **通話記錄**',
]);

export const SUMMARY_FIELD_KIND = Object.freeze({
  INTENT: 'intent',
  RESULT: 'result',
  TODO: 'todo',
  WARNING: 'warning',
  OTHER: 'other',
});

const FIELD_KIND_BY_LABEL = {
  意圖: SUMMARY_FIELD_KIND.INTENT,
  結果: SUMMARY_FIELD_KIND.RESULT,
  待辦: SUMMARY_FIELD_KIND.TODO,
  警示: SUMMARY_FIELD_KIND.WARNING,
};

// Blocks whose content belongs elsewhere: the agent's variables (roomName,
// fsCallerUuid…) go to the technical tab; the transcript has its own tab.
const TECHNICAL_HEADING = 'Agent 自訂欄位';
const TRANSCRIPT_HEADING = '逐字稿';

// Whitespace runs are spelled out as [ \t] next to "\n" and a non-space first
// character, so no two quantifiers can match the same text (no backtracking).
const BLOCK_SEPARATOR = /\n[ \t]*-{3,}[ \t]*\n/;
const BLOCK_HEADING = /^\*\*([^*]+)\*\*$/;
// "**意圖**：…", optionally after an emoji ("⚠️ **警示**：…").
const SUMMARY_FIELD = /^(?:\S+ )?\*\*([^*]+)\*\*[：:][ \t]*(\S.*)$/;
const LIST_FIELD = /^- ([^:：]+)[:：][ \t]*(\S.*)?$/;

/** The voice bridge's post-call summary note. */
export const isCallSummaryNote = message =>
  isCallNote(message) &&
  CALL_SUMMARY_NOTE_PREFIXES.some(prefix => message.content.startsWith(prefix));

/**
 * The newest summary note: the bridge posts one per call (it remembers having
 * posted), so an older one only appears if it was ever posted twice.
 * @param {Object[]} notes call notes, oldest first
 */
export const latestSummaryNote = notes =>
  notes.findLast(isCallSummaryNote) || null;

const fieldOf = (label, text) => ({
  kind: FIELD_KIND_BY_LABEL[label] || SUMMARY_FIELD_KIND.OTHER,
  label,
  text,
});

/**
 * @param {string} content the summary note's markdown
 * @returns {{ fields: Object[], body: string, footer: string, technical: Object[] }}
 */
export const parseCallSummaryNote = content => {
  const [head = '', ...blocks] = content
    .split(BLOCK_SEPARATOR)
    .map(block => block.trim())
    .filter(Boolean);

  const fields = [];
  const bodyLines = [];
  // The first line is the 📞 header; the card has its own title.
  head
    .split('\n')
    .slice(1)
    .forEach(line => {
      const match = SUMMARY_FIELD.exec(line.trim());
      if (match) {
        fields.push(fieldOf(match[1].trim(), match[2].trim()));
      } else {
        bodyLines.push(line);
      }
    });

  const technical = [];
  const footer = [];
  blocks.forEach(block => {
    const [first, ...lines] = block.split('\n');
    const heading = BLOCK_HEADING.exec(first.trim())?.[1].trim();
    if (heading === TECHNICAL_HEADING) {
      lines.forEach(line => {
        const match = LIST_FIELD.exec(line.trim());
        if (match) {
          technical.push({ key: match[1].trim(), value: match[2] ?? '' });
        }
      });
      return;
    }
    if (heading !== TRANSCRIPT_HEADING) footer.push(block);
  });

  return {
    fields,
    body: bodyLines.join('\n').trim(),
    footer: footer.join('\n\n'),
    technical,
  };
};

/**
 * The call's structured `summary`, in the same shape.
 * @param {Object} summary { intent?, result?, todos?, warnings?, text? }
 * @param {Function} t vue-i18n's t, for the field labels
 */
export const structuredCallSummary = (summary, t) => {
  const field = (kind, label, text) => ({ kind, label, text });
  const todo = t('CALLS_PAGE.SHEET.SUMMARY_FIELDS.TODO');
  const warning = t('CALLS_PAGE.SHEET.SUMMARY_FIELDS.WARNING');
  return {
    fields: [
      summary.intent &&
        field(
          SUMMARY_FIELD_KIND.INTENT,
          t('CALLS_PAGE.SHEET.SUMMARY_FIELDS.INTENT'),
          summary.intent
        ),
      summary.result &&
        field(
          SUMMARY_FIELD_KIND.RESULT,
          t('CALLS_PAGE.SHEET.SUMMARY_FIELDS.RESULT'),
          summary.result
        ),
      ...(summary.todos || []).map(text =>
        field(SUMMARY_FIELD_KIND.TODO, todo, text)
      ),
      ...(summary.warnings || []).map(text =>
        field(SUMMARY_FIELD_KIND.WARNING, warning, text)
      ),
    ].filter(Boolean),
    body: summary.text || '',
    footer: '',
    technical: [],
  };
};
