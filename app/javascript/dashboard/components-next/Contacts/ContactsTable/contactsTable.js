import { differenceInDays, fromUnixTime, getUnixTime } from 'date-fns';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { dynamicTime } from 'shared/helpers/timeHelper';

// Channel categories rather than brand logos: the column only says how the contact reached us.
const PHONE_ICON = 'i-lucide-phone';
const MESSAGE_ICON = 'i-lucide-message-circle';
const SOURCE_ICONS = {
  [INBOX_TYPES.EMAIL]: 'i-lucide-mail',
  [INBOX_TYPES.WEB]: 'i-lucide-globe',
  [INBOX_TYPES.VOICE]: PHONE_ICON,
  [INBOX_TYPES.TWILIO]: PHONE_ICON,
  [INBOX_TYPES.SMS]: PHONE_ICON,
  [INBOX_TYPES.FB]: MESSAGE_ICON,
  [INBOX_TYPES.INSTAGRAM]: MESSAGE_ICON,
  [INBOX_TYPES.LINE]: MESSAGE_ICON,
  [INBOX_TYPES.TELEGRAM]: MESSAGE_ICON,
  [INBOX_TYPES.WHATSAPP]: MESSAGE_ICON,
};

export const sourceIcon = channelType =>
  SOURCE_ICONS[channelType] ?? 'i-lucide-inbox';

const PHONE_LIKE = /^\+?[\d\s().-]{6,}$/;

/**
 * Whether the name still only repeats the contact's phone number or email (or the email's local
 * part), i.e. nobody has told us who this is yet.
 */
export const isUnknownName = ({ name, email }) => {
  const value = name?.trim().toLowerCase();
  if (!value) return true;
  if (PHONE_LIKE.test(value)) return true;
  const address = email?.trim().toLowerCase();
  return !!address && (value === address || value === address.split('@')[0]);
};

// Activity within the week reads at full strength; older activity fades in two steps.
const RECENT_DAYS = 7;
const STALE_DAYS = 30;

export const activityToneClass = (time, now = new Date()) => {
  const days = differenceInDays(now, fromUnixTime(time));
  if (days <= RECENT_DAYS) return 'text-n-slate-12';
  if (days <= STALE_DAYS) return 'text-n-slate-11';
  return 'text-n-slate-10';
};

// Only web links render as anchors; anything else stays plain text.
export const isWebUrl = value => /^https?:\/\//i.test(String(value ?? ''));

/**
 * How an extra (custom attribute) column shows a value.
 * @returns {{ text: string, href?: string }}
 */
export const customAttributeCell = (displayType, value, { yes, no }) => {
  if (value === undefined || value === null || value === '') {
    return { text: '' };
  }
  if (displayType === 'link' && isWebUrl(value)) {
    return { text: value, href: value };
  }
  if (displayType === 'date') {
    return { text: dynamicTime(getUnixTime(new Date(value))) };
  }
  if (displayType === 'checkbox') {
    return { text: value ? yes : no };
  }
  return { text: String(value) };
};
