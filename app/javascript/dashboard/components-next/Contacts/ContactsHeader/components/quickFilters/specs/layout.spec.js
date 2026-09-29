import { fitPillCount } from '../layout';

const widths = {
  pillWidths: [100, 100, 100, 100],
  overflowWidth: 60,
  advancedWidth: 80,
  actionsWidth: 0,
  gap: 8,
  actionsGap: 16,
};

describe('fitPillCount', () => {
  it('shows every pill when the whole row fits', () => {
    // 4 × (100 + 8) + 80
    expect(fitPillCount({ ...widths, barWidth: 512 })).toBe(4);
  });

  it('collapses from the end and keeps room for the overflow button', () => {
    // room after overflow and advanced: 400 - (60 + 8 + 80) = 252 → two pills
    expect(fitPillCount({ ...widths, barWidth: 400 })).toBe(2);
  });

  it('leaves room for the actions beside the row', () => {
    // 600 - 120 - 16 = 464 beside the actions; room 464 - 148 = 316 → two pills
    expect(fitPillCount({ ...widths, barWidth: 600, actionsWidth: 120 })).toBe(
      2
    );
  });

  it('wraps the actions below once not even the minimal row fits beside them', () => {
    // 260 - 120 - 16 = 124 < 148, so the row takes the full 260: room 112 → one pill
    expect(fitPillCount({ ...widths, barWidth: 260, actionsWidth: 120 })).toBe(
      1
    );
  });

  it('collapses every pill when only the buttons fit', () => {
    expect(fitPillCount({ ...widths, barWidth: 150 })).toBe(0);
  });
});
