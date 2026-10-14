import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import CallDetailSheet from '../CallDetailSheet.vue';
import CallContactPopover from '../CallContactPopover.vue';

withFullI18n('zh_TW');

const { session, notesState } = vi.hoisted(() => ({
  session: {},
  notesState: {},
}));

vi.mock('dashboard/composables/usePathorsCallSession', () => ({
  usePathorsCallSession: () => session,
  PATHORS_JOIN_ERROR_LABELS: {},
}));
vi.mock('dashboard/composables/useCallNotes', async importOriginal => ({
  ...(await importOriginal()),
  useCallNotes: conversationId => {
    notesState.conversationId = conversationId;
    return notesState;
  },
}));
vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { dismiss: vi.fn(), resolveFollowUp: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const ME = 9;
const NOW_SECONDS = () => Math.floor(Date.now() / 1000);

// The voice bridge's post-call note, as pathorsAI/pathors buildCallNote writes it.
const SUMMARY_NOTE_CONTENT = [
  '📞 **通話摘要**（AI 生成）',
  '',
  '**意圖**：了解派斯科技的服務內容',
  '**結果**：AI 介紹了服務並提議 **實機 Demo**',
  '**待辦**：安排實機 Demo',
  '⚠️ **警示**：客人提到競品',
  '',
  '---',
  '',
  '⏱ 3 分 12 秒 · completed',
  '🔗 [完整逐字稿與錄音](https://app.pathors.com/project/p/history/s)',
  '',
  '---',
  '',
  '**Agent 自訂欄位**',
  '- roomName: room-abc',
  '- fsCallerUuid: uuid-123',
  '',
  '---',
  '',
  '**逐字稿**',
  'AI：您好',
  '客戶：你好我想問報價',
].join('\n');

const note = (id, content, overrides = {}) => ({
  id,
  private: true,
  content_type: 'text',
  content,
  created_at: 1_760_000_000 + id,
  conversation_id: 12,
  sender: { available_name: '小林' },
  ...overrides,
});
const SUMMARY_NOTE = note(5, SUMMARY_NOTE_CONTENT, {
  sender: { available_name: 'Pathors' },
});
const HUMAN_NOTE = note(4, '客人**下午**三點後方便回撥');

const buildCall = overrides => ({
  id: 77,
  callId: 'sip-1c20',
  provider: 'pathors',
  status: 'in-progress',
  startedAt: NOW_SECONDS() - 60,
  fromNumber: '+886933963188',
  direction: 'inbound',
  inbox: { name: '派斯科技代表號碼' },
  conversation: { displayId: 12 },
  acceptedByAgentId: null,
  live: { seq: 3, turns: 2, interruptions: 0, transcript: [] },
  ...overrides,
});

const endedCall = overrides =>
  buildCall({
    status: 'completed',
    durationSeconds: 192,
    live: {
      seq: 9,
      turns: 6,
      interruptions: 1,
      transcript: [{ kind: 'message', role: 'assistant', content: '您好' }],
    },
    ...overrides,
  });

const dompurifyHtml = {
  mounted: (el, { value }) => {
    el.innerHTML = value;
  },
  updated: (el, { value }) => {
    el.innerHTML = value;
  },
};

const mountSheet = call =>
  mount(CallDetailSheet, {
    props: { call, accountId: 1, currentUserId: ME },
    global: {
      stubs: { RouterLink: true, AudioPlayer: true, CallContactPopover: true },
      directives: { 'dompurify-html': dompurifyHtml },
    },
  });

const find = (wrapper, id) => wrapper.find(`[data-test-id="${id}"]`);
const tabLabels = wrapper =>
  wrapper
    .findComponent(TabBar)
    .props('tabs')
    .map(tab => tab.label);
const activeTabLabel = wrapper => {
  const bar = wrapper.findComponent(TabBar);
  return bar.props('tabs')[bar.props('initialActiveTab')].label;
};
const pickTab = async (wrapper, label) => {
  const bar = wrapper.findComponent(TabBar);
  bar.vm.$emit(
    'tabChanged',
    bar.props('tabs').find(tab => tab.label === label)
  );
  await wrapper.vm.$nextTick();
};
const metric = (wrapper, key) => wrapper.find(`[data-metric="${key}"]`);

describe('CallDetailSheet', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    useAlert.mockReset();
    Object.assign(session, {
      join: vi.fn(),
      hangup: vi.fn(),
      enableAudio: vi.fn(),
      isActiveCall: id => id === session.activeCallId.value,
      isAudioBlocked: ref(false),
      isJoining: ref(false),
      isJoined: ref(false),
      isHangingUp: ref(false),
      error: ref(null),
      durationSeconds: ref(0),
      activeCallId: ref(null),
    });
    Object.assign(notesState, {
      notes: ref([]),
      isLoading: ref(false),
      hasLoadError: ref(false),
      isSaving: ref(false),
      create: vi.fn().mockResolvedValue(true),
    });
  });

  describe('while the AI handles the call', () => {
    it('opens on the live transcript, with the metrics above and quick tags below', () => {
      const wrapper = mountSheet(
        buildCall({
          live: {
            seq: 3,
            turns: 2,
            interruptions: 0,
            transcript: [
              { kind: 'message', role: 'assistant', content: '您好' },
            ],
          },
        })
      );

      expect(tabLabels(wrapper)).toEqual(['即時逐字稿', '擷取資料', '備註']);
      expect(activeTabLabel(wrapper)).toBe('即時逐字稿');
      expect(find(wrapper, 'call-tab-transcript').text()).toContain('您好');
      expect(find(wrapper, 'call-metrics').text()).toContain('通話時間');
      expect(find(wrapper, 'call-metrics').text()).toContain('上限 05:00');
      expect(find(wrapper, 'call-quick-tags').exists()).toBe(true);
    });

    it('keeps the status band and the metrics fixed and scrolls only the open tab', async () => {
      const wrapper = mountSheet(
        buildCall({
          live: {
            seq: 3,
            transcript: [
              { kind: 'message', role: 'assistant', content: '您好' },
            ],
          },
        })
      );
      const sheet = find(wrapper, 'call-detail-sheet');
      const band = find(wrapper, 'call-status-bar');

      expect(band.element.parentElement).toBe(sheet.element);
      expect(band.classes()).toContain('shrink-0');
      expect(
        sheet
          .findAll('.overflow-y-auto')
          .map(el => el.attributes('data-test-id'))
      ).toEqual(['call-transcript']);

      await pickTab(wrapper, '擷取資料');
      expect(
        sheet
          .findAll('.overflow-y-auto')
          .map(el => el.attributes('data-test-id'))
      ).toEqual(['call-tab-variables']);
    });

    it('says the captured data comes with a takeover when there is none yet', async () => {
      const wrapper = mountSheet(buildCall());
      await pickTab(wrapper, '擷取資料');

      expect(find(wrapper, 'call-variables-empty').text()).toBe(
        'AI 擷取的資料會在有人接手時一起交過來。'
      );
    });

    it('offers taking over as a solid blue button', () => {
      const wrapper = mountSheet(buildCall());
      const button = find(wrapper, 'call-take-over');

      expect(button.classes()).toEqual(
        expect.arrayContaining(['bg-n-brand', 'h-10'])
      );
      expect(button.attributes('disabled')).toBeUndefined();
    });

    it('adds a quick tag as a private note stamped with the call time', async () => {
      const wrapper = mountSheet(
        buildCall({ startedAt: new Date(Date.now() - 86_000).toISOString() })
      );

      await wrapper.find('[data-tag="CALL_BACK"]').trigger('click');
      await flushPromises();

      expect(notesState.create).toHaveBeenCalledWith(
        '［標註］需回撥 · 通話 01:26'
      );
      expect(useAlert).not.toHaveBeenCalled();
    });

    it('says so when a quick tag could not be saved', async () => {
      notesState.create.mockResolvedValue(false);
      const wrapper = mountSheet(buildCall());

      await wrapper.find('[data-tag="QUOTE"]').trigger('click');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith('無法儲存備註');
    });

    it('keeps the AI summary note in the notes while nothing else shows it', async () => {
      notesState.notes.value = [HUMAN_NOTE, SUMMARY_NOTE];
      const wrapper = mountSheet(buildCall());
      await pickTab(wrapper, '備註');

      expect(wrapper.findAll('[data-test-id="call-note"]')).toHaveLength(2);
    });
  });

  describe('metrics', () => {
    it('turns each metric amber only once it goes past its limit', () => {
      const atLimit = mountSheet(
        buildCall({
          startedAt: NOW_SECONDS() - 300,
          live: { seq: 3, turns: 20, interruptions: 3, transcript: [] },
        })
      );
      ['duration', 'turns', 'interruptions'].forEach(key => {
        expect(metric(atLimit, key).attributes('data-over')).toBe('false');
      });

      const pastLimit = mountSheet(
        buildCall({
          startedAt: NOW_SECONDS() - 302,
          live: { seq: 3, turns: 21, interruptions: 4, transcript: [] },
        })
      );
      ['duration', 'turns', 'interruptions'].forEach(key => {
        expect(metric(pastLimit, key).attributes('data-over')).toBe('true');
        expect(metric(pastLimit, key).find('dd').classes()).toContain(
          'text-n-amber-11'
        );
      });
      expect(metric(pastLimit, 'turns').text()).toContain('上限 20');
      expect(metric(pastLimit, 'interruptions').text()).toContain('上限 3');
    });

    it('shows them on an ended call too, from its duration', () => {
      const wrapper = mountSheet(endedCall({ durationSeconds: 412 }));
      const summaryTab = find(wrapper, 'call-tab-summary');

      expect(summaryTab.find('[data-test-id="call-metrics"]').exists()).toBe(
        true
      );
      expect(metric(wrapper, 'duration').text()).toContain('06:52');
      expect(metric(wrapper, 'duration').attributes('data-over')).toBe('true');
      expect(metric(wrapper, 'turns').text()).toContain('6');
    });
  });

  describe('once a human has the call', () => {
    it('switches to the takeover layout after taking it over', async () => {
      session.join.mockResolvedValue(true);
      const startedAt = NOW_SECONDS() - 200;
      const wrapper = mountSheet(buildCall({ startedAt }));
      await pickTab(wrapper, '備註');

      await find(wrapper, 'call-take-over').trigger('click');
      expect(session.join).toHaveBeenCalledWith({ accountId: 1, callId: 77 });

      await wrapper.setProps({
        call: buildCall({
          startedAt,
          acceptedByAgentId: ME,
          acceptedByAgentName: 'Grace',
          acceptedAt: (startedAt + 86) * 1000,
          variables: { 產業: '保全', 姓名: null },
        }),
      });

      expect(tabLabels(wrapper)).toEqual(['接手資訊', '逐字稿', '備註']);
      expect(activeTabLabel(wrapper)).toBe('接手資訊');
      expect(find(wrapper, 'call-quick-tags').exists()).toBe(false);
      expect(metric(wrapper, 'duration').text()).toContain('接手前通話時間');
      expect(metric(wrapper, 'duration').text()).toContain('01:26');

      const handoff = find(wrapper, 'call-tab-handoff');
      expect(handoff.text()).toContain('AI 擷取的資料 · 接手當下');
      expect(handoff.text()).toContain('保全');
      expect(handoff.text()).toContain('未取得');
    });

    it('leaves out what came before the takeover when there is no summary', () => {
      const wrapper = mountSheet(
        buildCall({ acceptedByAgentId: ME, acceptedByAgentName: 'Grace' })
      );

      expect(find(wrapper, 'call-tab-handoff').text()).not.toContain(
        '接手前重點'
      );
      expect(find(wrapper, 'call-summary').exists()).toBe(false);
    });

    it('treats a connected transfer as handed off', () => {
      const wrapper = mountSheet(
        buildCall({
          live: {
            seq: 3,
            transcript: [],
            attention: { transfer: { phase: 'connected', at: Date.now() } },
          },
        })
      );

      expect(activeTabLabel(wrapper)).toBe('接手資訊');
    });

    it('offers hanging up as a ruby button of the same size once in the call', () => {
      session.isJoined.value = true;
      session.activeCallId.value = 77;
      const wrapper = mountSheet(
        buildCall({ acceptedByAgentId: ME, acceptedByAgentName: 'Grace' })
      );

      expect(find(wrapper, 'call-take-over').exists()).toBe(false);
      expect(find(wrapper, 'call-hang-up').classes()).toEqual(
        expect.arrayContaining(['bg-n-ruby-9', 'h-10'])
      );
      expect(find(wrapper, 'call-status-bar').text()).toContain('你正在通話中');
    });
  });

  describe('once the call ended', () => {
    it('opens on the summary, with the technical tab last', () => {
      const wrapper = mountSheet(endedCall());

      expect(tabLabels(wrapper)).toEqual([
        '摘要',
        '備註',
        '逐字稿',
        '技術資訊',
      ]);
      expect(activeTabLabel(wrapper)).toBe('摘要');
      expect(find(wrapper, 'call-quick-tags').exists()).toBe(false);
      // The metrics move into the summary.
      expect(wrapper.findAll('[data-test-id="call-metrics"]')).toHaveLength(1);
    });

    it('renders the AI summary note as a card, without markdown symbols', () => {
      notesState.notes.value = [HUMAN_NOTE, SUMMARY_NOTE];
      const wrapper = mountSheet(endedCall());
      const card = find(wrapper, 'call-summary');

      expect(card.text()).not.toContain('**');
      expect(card.findAll('dt').map(dt => dt.text())).toEqual([
        '意圖',
        '結果',
        '待辦',
        '警示',
      ]);
      expect(card.find('strong').text()).toBe('實機 Demo');
      expect(card.find('[data-kind="todo"]').classes()).toContain(
        'text-n-amber-11'
      );
      expect(card.find('a').attributes('href')).toBe(
        'https://app.pathors.com/project/p/history/s'
      );
      expect(card.find('a').text()).toBe('完整逐字稿與錄音');
      expect(card.text()).not.toContain('客戶：你好我想問報價');
    });

    it('keeps technical fields to the technical tab', async () => {
      notesState.notes.value = [SUMMARY_NOTE];
      const wrapper = mountSheet(endedCall());

      expect(wrapper.text()).not.toContain('roomName');
      expect(wrapper.text()).not.toContain('fsCallerUuid');
      await pickTab(wrapper, '備註');
      expect(wrapper.text()).not.toContain('roomName');

      await pickTab(wrapper, '技術資訊');
      const technical = find(wrapper, 'call-technical');
      expect(technical.text()).toContain('roomName');
      expect(technical.text()).toContain('room-abc');
      expect(technical.text()).toContain('fsCallerUuid');
      expect(technical.text()).toContain('sip-1c20');
    });

    it('does not list the note it shows as the summary among the notes', async () => {
      notesState.notes.value = [HUMAN_NOTE, SUMMARY_NOTE];
      const wrapper = mountSheet(endedCall());

      const latest = find(wrapper, 'call-latest-note');
      expect(latest.text()).toContain('客人下午三點後方便回撥');
      expect(latest.text()).not.toContain('**');

      await pickTab(wrapper, '備註');
      const notes = wrapper.findAll('[data-test-id="call-note"]');
      expect(notes).toHaveLength(1);
      expect(notes[0].text()).toContain('小林');
      expect(notes[0].find('strong').text()).toBe('下午');
    });

    it('falls back to the call’s structured summary', () => {
      const wrapper = mountSheet(
        endedCall({
          summary: {
            intent: '問報價',
            result: '已說明方案',
            todos: ['寄報價單'],
          },
        })
      );
      const card = find(wrapper, 'call-summary');

      expect(card.findAll('dt').map(dt => dt.text())).toEqual([
        '意圖',
        '結果',
        '待辦',
      ]);
      expect(card.text()).toContain('寄報價單');
    });

    it('says there is no summary yet before the AI posts one', () => {
      const wrapper = mountSheet(endedCall());

      expect(find(wrapper, 'call-tab-summary').text()).toContain(
        '還沒有 AI 摘要'
      );
      expect(find(wrapper, 'call-latest-note').text()).toContain('還沒有備註');
    });

    it('shows what the AI extracted at takeover in the summary', () => {
      const wrapper = mountSheet(
        endedCall({
          acceptedByAgentId: ME,
          variables: { 姓名: '林先生', Email: null },
        })
      );
      const section = find(wrapper, 'call-variables');

      expect(section.text()).toContain('AI 擷取的資料 · 接手當下');
      expect(section.text()).toContain('林先生');
      expect(section.text()).toContain('未取得');
    });

    it('puts the recording above the transcript', async () => {
      const wrapper = mountSheet(
        endedCall({ recordingUrl: 'https://example.com/a.mp3' })
      );
      await pickTab(wrapper, '逐字稿');

      const tab = find(wrapper, 'call-tab-transcript');
      expect(tab.text()).toContain('錄音');
      expect(tab.findComponent({ name: 'AudioPlayer' }).exists()).toBe(true);
      expect(tab.text()).toContain('您好');
    });
  });

  it('opens the new phase on its first tab when the call moves on', async () => {
    const wrapper = mountSheet(buildCall());
    await pickTab(wrapper, '備註');
    expect(activeTabLabel(wrapper)).toBe('備註');

    await wrapper.setProps({ call: endedCall() });

    expect(activeTabLabel(wrapper)).toBe('摘要');
  });

  it('turns the take-over button ruby when the AI asks for help', () => {
    const wrapper = mountSheet(
      buildCall({
        needsAction: true,
        live: {
          seq: 3,
          transcript: [],
          attention: {
            takeoverRequest: { reason: 'caller_request', at: Date.now() },
          },
        },
      })
    );

    expect(find(wrapper, 'call-status-bar').attributes('data-state')).toBe(
      'requested'
    );
    expect(find(wrapper, 'call-take-over').classes()).toEqual(
      expect.arrayContaining(['bg-n-ruby-9', 'h-10'])
    );
  });

  it('keeps the take-over button in sight but disabled during a transfer, and says why', () => {
    const wrapper = mountSheet(
      buildCall({
        live: {
          seq: 3,
          transcript: [],
          attention: {
            transfer: { phase: 'dialing', targetMasked: '****8783' },
          },
        },
      })
    );

    expect(
      find(wrapper, 'call-take-over').attributes('disabled')
    ).toBeDefined();
    expect(find(wrapper, 'call-status-bar').text()).toContain('撥號中不能接手');
    expect(find(wrapper, 'call-take-over').text()).toBe('接手通話');
  });

  it('offers taking over a transfer that is still ringing, cancelling it', () => {
    const wrapper = mountSheet(
      buildCall({
        live: {
          seq: 3,
          transcript: [],
          attention: {
            transfer: {
              phase: 'dialing',
              targetMasked: '****8783',
              cancellable: true,
            },
          },
        },
      })
    );
    const button = find(wrapper, 'call-take-over');
    const band = find(wrapper, 'call-status-bar');

    expect(button.attributes('disabled')).toBeUndefined();
    expect(button.text()).toBe('接手（取消轉接）');
    expect(button.classes()).toEqual(
      expect.arrayContaining(['bg-n-brand', 'h-10'])
    );
    expect(band.attributes('data-state')).toBe('dialing');
    expect(band.text()).toContain('正在撥給 ****8783，你可以先接');
    expect(band.text()).not.toContain('撥號中不能接手');
  });

  it('shows the person on the call, not a failed transfer, once a human took over a ringing one', () => {
    const wrapper = mountSheet(
      buildCall({
        acceptedByAgentId: 3,
        acceptedByAgentName: 'Amy',
        acceptedAt: Date.now() - 5_000,
        needsAction: false,
        live: {
          seq: 3,
          transcript: [],
          attention: {
            transfer: {
              phase: 'failed',
              failureReason: 'human_takeover',
              at: Date.now(),
            },
          },
        },
      })
    );
    const band = find(wrapper, 'call-status-bar');

    expect(band.attributes('data-state')).toBe('human');
    expect(band.classes()).toContain('bg-n-blue-2');
    expect(band.text()).not.toContain('轉接失敗');
  });

  it('has no way out to the conversation', () => {
    const wrapper = mountSheet(buildCall());

    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
    expect(wrapper.text()).not.toContain('開啟對話');
  });

  it("reads the notes of the call's conversation, from a list row or a live record", () => {
    mountSheet(buildCall());
    expect(notesState.conversationId.value).toBe(12);

    mountSheet(buildCall({ conversation: undefined, conversationId: 34 }));
    expect(notesState.conversationId.value).toBe(34);
  });

  it('opens the caller from the title and passes on an earlier call picked there', () => {
    const wrapper = mountSheet(buildCall());
    const contact = wrapper.findComponent(CallContactPopover);

    expect(contact.props('title')).toBe('+886933963188');
    contact.vm.$emit('openCall', 55);

    expect(wrapper.emitted('openCall')).toEqual([[55]]);
  });
});
