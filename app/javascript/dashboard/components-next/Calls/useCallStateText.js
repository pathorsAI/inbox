import { useI18n } from 'vue-i18n';
import { CALL_STATE } from 'dashboard/helper/pathorsCallState';

/** The AI's one-line take on an ended call, in order of usefulness. */
export const summaryText = summary =>
  summary?.text || summary?.result || summary?.intent || '';

/**
 * The one line under a call's state — why it needs someone, where the transfer
 * is going, what the AI concluded — shared by the table, the sheet, the
 * attention alerts and the bubble.
 */
export function useCallStateText() {
  const { t } = useI18n();

  const join = parts => parts.filter(Boolean).join(' · ');

  const DETAIL_BY_STATE = {
    [CALL_STATE.REQUESTED]: (call, state) =>
      join([t(state.reasonKey), state.detail]),
    [CALL_STATE.TRANSFER_FAILED]: (call, state) =>
      join([
        state.target &&
          t('CALLS_PAGE.DETAIL.TRANSFER_TARGET', { target: state.target }),
        state.reasonKey && t(state.reasonKey),
      ]),
    [CALL_STATE.DIALING]: (call, state) =>
      state.target
        ? t('CALLS_PAGE.DETAIL.DIALING', { target: state.target })
        : '',
    [CALL_STATE.TRANSFERRED]: (call, state) =>
      state.target
        ? t('CALLS_PAGE.DETAIL.TRANSFERRED_TO', { target: state.target })
        : '',
    [CALL_STATE.WARN]: (call, state) =>
      join(state.alerts.map(alert => t(alert.labelKey, alert.params))),
    [CALL_STATE.ENDED]: call => summaryText(call.summary),
  };

  const stateLabel = state => t(state.labelKey, state.labelParams);

  const stateDetail = (call, state) =>
    DETAIL_BY_STATE[state.key]?.(call, state) || '';

  return { stateLabel, stateDetail };
}
