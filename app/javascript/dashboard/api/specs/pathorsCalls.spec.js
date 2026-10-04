import pathorsCallsAPI from '../pathorsCalls';
import ApiClient from '../ApiClient';

describe('#PathorsCallsAPI', () => {
  it('creates correct instance', () => {
    expect(pathorsCallsAPI).toBeInstanceOf(ApiClient);
    expect(pathorsCallsAPI).toHaveProperty('join');
    expect(pathorsCallsAPI).toHaveProperty('hangup');
    expect(pathorsCallsAPI).toHaveProperty('active');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve({ data: { ok: true } })),
      get: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      axiosMock.post.mockClear();
      axiosMock.get.mockClear();
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#join posts to the account-scoped join route', async () => {
      await pathorsCallsAPI.join(42, 3);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/3/pathors/calls/42/join'
      );
    });

    it('#hangup posts to the account-scoped hangup route and returns data', async () => {
      const data = await pathorsCallsAPI.hangup(42, 3);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/3/pathors/calls/42/hangup'
      );
      expect(data).toEqual({ ok: true });
    });

    it('#active gets the live calls and returns data', async () => {
      const data = await pathorsCallsAPI.active();
      expect(axiosMock.get).toHaveBeenCalledWith(
        expect.stringMatching(/\/pathors\/calls\/active$/)
      );
      expect(data).toEqual({ payload: [] });
    });
  });
});
