/**
 * How many pills, in priority order, fit on the filter bar. The pill row always ends with the
 * advanced button and gains the overflow button once any pill collapses. The actions sit beside
 * the row; when not even the overflow and advanced buttons fit next to them, they wrap below
 * and the row gets the whole width.
 * @param {Object} widths - Measured widths in px.
 * @param {number} widths.barWidth
 * @param {number[]} widths.pillWidths
 * @param {number} widths.overflowWidth
 * @param {number} widths.advancedWidth
 * @param {number} widths.actionsWidth - 0 when the actions are hidden.
 * @param {number} widths.gap - Gap between items in the row.
 * @param {number} widths.actionsGap - Gap between the row and the actions.
 * @returns {number}
 */
export const fitPillCount = ({
  barWidth,
  pillWidths,
  overflowWidth,
  advancedWidth,
  actionsWidth,
  gap,
  actionsGap,
}) => {
  const besideActions = actionsWidth
    ? barWidth - actionsWidth - actionsGap
    : barWidth;
  const fullRow = pillWidths.reduce(
    (sum, width) => sum + width + gap,
    advancedWidth
  );
  if (fullRow <= besideActions) return pillWidths.length;

  const minimalRow = overflowWidth + gap + advancedWidth;
  const rowWidth = besideActions >= minimalRow ? besideActions : barWidth;
  if (fullRow <= rowWidth) return pillWidths.length;

  let room = rowWidth - minimalRow;
  let count = 0;
  while (count < pillWidths.length && pillWidths[count] + gap <= room) {
    room -= pillWidths[count] + gap;
    count += 1;
  }
  return count;
};
