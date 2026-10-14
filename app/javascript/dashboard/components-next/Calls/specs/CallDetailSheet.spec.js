import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import CallDetailSheet from '../CallDetailSheet.vue';
import CallContactPopover from '../CallContactPopover.vue';
import CallNotes from '../CallNotes.vue';

withFullI18n('zh_TW');

const { session } = vi.hoisted(() => ({ session: {} }));

vi.mock('dashboard/composables/usePathorsCallSession', () => ({
  usePathorsCallSession: () => session,
  PATHORS_JOIN_ERROR_LABELS: {},
}));
vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { dismiss: vi.fn(), resolveFollowUp: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const ME = 9;

const buildCall = overrides => ({
  id: 77,
  provider: 'pathors',
  status: 'in-progress',
  startedAt: Math.floor(Date.now() / 1000) - 60,
  fromNumber: '+886933963188',
  direction: 'inbound',
  inbox: { name: '派斯科技代表號碼' },
  conversation: { displayId: 12 },
  acceptedByAgentId: null,
  live: { seq: 3, turns: 2, interruptions: 0, transcript: [] },
  ...overrides,
});

const mountSheet = call =>
  mount(CallDetailSheet, {
    props: { call, accountId: 1, currentUserId: ME },
    global: {
      stubs: {
        RouterLink: true,
        AudioPlayer: true,
        CallNotes: true,
        CallContactPopover: true,
      },
    },
  });

const find = (wrapper, id) => wrapper.find(`[data-test-id="${id}"]`);

describe('CallDetailSheet', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
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
  });

  it('keeps the status band out of the body and scrolls only the transcript and the side column', () => {
    const wrapper = mountSheet(
      buildCall({
        live: {
          seq: 3,
          transcript: [{ kind: 'message', role: 'assistant', content: '您好' }],
        },
      })
    );
    const sheet = find(wrapper, 'call-detail-sheet');
    const band = find(wrapper, 'call-status-bar');

    expect(band.element.parentElement).toBe(sheet.element);
    expect(band.classes()).toContain('shrink-0');
    expect(
      sheet.findAll('.overflow-y-auto').map(el => el.attributes('data-test-id'))
    ).toEqual(['call-transcript', 'call-detail-rail']);
  });

  it('offers taking over as a solid blue button while the AI handles the call', () => {
    const wrapper = mountSheet(buildCall());
    const button = find(wrapper, 'call-take-over');

    expect(button.classes()).toEqual(
      expect.arrayContaining(['bg-n-brand', 'h-10'])
    );
    expect(button.attributes('disabled')).toBeUndefined();
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

  it('takes over a ringing transfer through the join endpoint', async () => {
    session.join.mockResolvedValue(true);
    const wrapper = mountSheet(
      buildCall({
        live: {
          seq: 3,
          transcript: [],
          attention: { transfer: { phase: 'dialing', cancellable: true } },
        },
      })
    );

    await find(wrapper, 'call-take-over').trigger('click');

    expect(session.join).toHaveBeenCalledWith({ accountId: 1, callId: 77 });
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

  it('states the status once, without a call facts section', () => {
    const wrapper = mountSheet(
      buildCall({ acceptedByAgentId: ME, acceptedByAgentName: 'Grace' })
    );
    const rail = find(wrapper, 'call-detail-rail');

    expect(rail.text()).not.toContain('你正在通話中');
    expect(rail.text()).not.toContain('處理人');
    expect(rail.text()).not.toContain('派斯科技代表號碼');
  });

  it('puts what the AI extracted at takeover at the top of the side column', () => {
    const wrapper = mountSheet(
      buildCall({
        status: 'completed',
        durationSeconds: 192,
        summary: { text: '客人想直接跟業務談' },
        acceptedByAgentId: ME,
        variables: { 姓名: '林先生', Email: null },
      })
    );
    const rail = find(wrapper, 'call-detail-rail');
    const section = find(wrapper, 'call-variables');

    expect(rail.element.firstElementChild).toBe(section.element);
    expect(section.text()).toContain('AI 擷取的資料 · 接手當下');
    expect(section.text()).toContain('林先生');
    expect(section.text()).toContain('未取得');
  });

  it('shows the variables as soon as the call it was given carries them', async () => {
    const wrapper = mountSheet(buildCall({ acceptedByAgentId: ME }));
    expect(find(wrapper, 'call-variables').exists()).toBe(false);

    await wrapper.setProps({
      call: buildCall({ acceptedByAgentId: ME, variables: { 行業: '餐飲業' } }),
    });

    expect(find(wrapper, 'call-variables').text()).toContain('餐飲業');
  });

  it('has no way out to the conversation', () => {
    const wrapper = mountSheet(buildCall());

    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
    expect(wrapper.text()).not.toContain('開啟對話');
  });

  it("keeps the notes of the call's conversation, from a list row or a live record", () => {
    const fromList = mountSheet(buildCall());
    expect(fromList.findComponent(CallNotes).props('conversationId')).toBe(12);

    const fromLive = mountSheet(
      buildCall({ conversation: undefined, conversationId: 34 })
    );
    expect(fromLive.findComponent(CallNotes).props('conversationId')).toBe(34);
  });

  it('opens the caller from the title and passes on an earlier call picked there', () => {
    const wrapper = mountSheet(buildCall());
    const contact = wrapper.findComponent(CallContactPopover);

    expect(contact.props('title')).toBe('+886933963188');
    contact.vm.$emit('openCall', 55);

    expect(wrapper.emitted('openCall')).toEqual([[55]]);
  });
});
