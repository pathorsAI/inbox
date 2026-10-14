import {
  SUMMARY_FIELD_KIND,
  isCallSummaryNote,
  latestSummaryNote,
  parseCallSummaryNote,
  structuredCallSummary,
} from '../callSummary';

// pathorsAI/pathors buildCallNote, with a summary and every optional block.
const FULL_NOTE = [
  '📞 **通話摘要**（AI 生成）',
  '',
  '**意圖**：了解服務內容',
  '**結果**：已說明',
  '**待辦**：安排 Demo',
  '⚠️ **警示**：提到競品',
  '',
  '---',
  '',
  '⏱ 3 分 12 秒 · completed',
  '🔗 [完整逐字稿與錄音](https://app.pathors.com/s)',
  '',
  '---',
  '',
  '**Agent 自訂欄位**',
  '- roomName: room-abc',
  '- fsCallerUuid: uuid-1',
  '- 備註: a: b',
  '',
  '---',
  '',
  '**逐字稿**',
  'AI：您好',
].join('\n');

// The same note when the summary failed.
const NO_SUMMARY_NOTE = [
  '📞 **通話記錄**',
  '',
  '（通話過短或摘要產生失敗，請直接看逐字稿）',
  '',
  '---',
  '',
  '⏱ 8 秒 · completed',
  '🔗 [完整逐字稿與錄音](https://app.pathors.com/s)',
].join('\n');

const message = (id, content, overrides = {}) => ({
  id,
  private: true,
  content_type: 'text',
  content,
  ...overrides,
});

describe('isCallSummaryNote', () => {
  it("recognises the voice bridge's note by its header", () => {
    expect(isCallSummaryNote(message(1, FULL_NOTE))).toBe(true);
    expect(isCallSummaryNote(message(2, NO_SUMMARY_NOTE))).toBe(true);
  });

  it('leaves out notes people write, public messages and the call-start marker', () => {
    expect(isCallSummaryNote(message(1, '通話摘要：客人要報價'))).toBe(false);
    expect(isCallSummaryNote(message(2, FULL_NOTE, { private: false }))).toBe(
      false
    );
    expect(isCallSummaryNote(message(3, '📞 **Call in progress**'))).toBe(
      false
    );
  });
});

describe('latestSummaryNote', () => {
  it('picks the newest summary note', () => {
    const notes = [
      message(1, FULL_NOTE),
      message(2, '我來回撥'),
      message(3, NO_SUMMARY_NOTE),
      message(4, '已回撥'),
    ];

    expect(latestSummaryNote(notes).id).toBe(3);
    expect(latestSummaryNote([message(5, '已回撥')])).toBeNull();
  });
});

describe('parseCallSummaryNote', () => {
  it('splits the note into summary fields, footer and technical fields', () => {
    const parsed = parseCallSummaryNote(FULL_NOTE);

    expect(parsed.fields).toEqual([
      { kind: SUMMARY_FIELD_KIND.INTENT, label: '意圖', text: '了解服務內容' },
      { kind: SUMMARY_FIELD_KIND.RESULT, label: '結果', text: '已說明' },
      { kind: SUMMARY_FIELD_KIND.TODO, label: '待辦', text: '安排 Demo' },
      { kind: SUMMARY_FIELD_KIND.WARNING, label: '警示', text: '提到競品' },
    ]);
    expect(parsed.body).toBe('');
    expect(parsed.footer).toBe(
      '⏱ 3 分 12 秒 · completed\n🔗 [完整逐字稿與錄音](https://app.pathors.com/s)'
    );
    expect(parsed.technical).toEqual([
      { key: 'roomName', value: 'room-abc' },
      { key: 'fsCallerUuid', value: 'uuid-1' },
      { key: '備註', value: 'a: b' },
    ]);
  });

  it('leaves the transcript block to the transcript tab', () => {
    const parsed = parseCallSummaryNote(FULL_NOTE);

    expect(JSON.stringify(parsed)).not.toContain('AI：您好');
  });

  it('keeps text it cannot tell apart as a body to render whole', () => {
    const parsed = parseCallSummaryNote(NO_SUMMARY_NOTE);

    expect(parsed.fields).toEqual([]);
    expect(parsed.body).toBe('（通話過短或摘要產生失敗，請直接看逐字稿）');
    expect(parsed.technical).toEqual([]);
  });

  it('keeps a label it does not know as a plain field', () => {
    const parsed = parseCallSummaryNote(
      '📞 **通話摘要**（AI 生成）\n\n**情緒**：平穩'
    );

    expect(parsed.fields).toEqual([
      { kind: SUMMARY_FIELD_KIND.OTHER, label: '情緒', text: '平穩' },
    ]);
  });
});

describe('structuredCallSummary', () => {
  const t = key => key.split('.').at(-1);

  it("lays the call's own summary out in the same shape", () => {
    expect(
      structuredCallSummary(
        {
          intent: '問報價',
          result: '已說明',
          todos: ['寄報價單', '約 Demo'],
          warnings: ['語氣不耐'],
          text: '整體順利',
        },
        t
      )
    ).toEqual({
      fields: [
        { kind: 'intent', label: 'INTENT', text: '問報價' },
        { kind: 'result', label: 'RESULT', text: '已說明' },
        { kind: 'todo', label: 'TODO', text: '寄報價單' },
        { kind: 'todo', label: 'TODO', text: '約 Demo' },
        { kind: 'warning', label: 'WARNING', text: '語氣不耐' },
      ],
      body: '整體順利',
      footer: '',
      technical: [],
    });
  });
});
